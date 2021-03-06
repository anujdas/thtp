require 'rack'
require 'thrift'

require 'thtp/encoding'
require 'thtp/errors'
require 'thtp/middleware_stack'
require 'thtp/status'
require 'thtp/utils'

require 'thtp/server/instrumentation'
require 'thtp/server/middleware'
require 'thtp/server/pub_sub'
require 'thtp/server/null_route'

module THTP
  # An HTTP (Rack middleware) implementation of Thrift-RPC
  class Server
    include PubSub
    include Utils

    attr_reader :service

    # @param app [Object?] The Rack application underneath, if used as middleware
    # @param service [Thrift::Service] The service class handled by this server
    # @param handlers [Object,Array<Object>] The object(s) handling RPC requests
    def initialize(app = NullRoute.new, service:, handlers: [])
      @app = app
      @service = service
      @handler = MiddlewareStack.new(service, handlers)
      @route = %r{^/#{canonical_name(service)}/(?<rpc>[\w.]+)/?$} # /:service/:rpc
    end

    # delegate to RPC handler stack
    def use(middleware_class, *middleware_args)
      @handler.use(middleware_class, *middleware_args)
    end

    # Rack implementation entrypoint
    def call(rack_env)
      start_time = get_time
      # verify routing
      request = Rack::Request.new(rack_env)
      protocol = Encoding.protocol(request.media_type) || Thrift::JsonProtocol
      return @app.call(rack_env) unless request.post? && @route.match(request.path_info)
      # get RPC name from route
      rpc = Regexp.last_match[:rpc]
      raise UnknownRpcError, rpc unless @handler.respond_to?(rpc)
      # read, perform, write
      args = read_args(request.body, rpc, protocol)
      result = @handler.public_send(rpc, *args)
      write_reply(result, rpc, protocol).tap do
        publish :rpc_success,
                request: request, rpc: rpc, args: args, result: result, time: elapsed_ms(start_time)
      end
    rescue Thrift::Exception => e # known schema-defined Thrift errors
      write_reply(e, rpc, protocol).tap do
        publish :rpc_exception,
                request: request, rpc: rpc, args: args, exception: e, time: elapsed_ms(start_time)
      end
    rescue ServerError => e # known server/communication errors
      write_error(e, protocol).tap do
        publish :rpc_error,
                request: request, rpc: rpc, args: args, error: e, time: elapsed_ms(start_time)
      end
    rescue => e # a non-Thrift exception occurred; translate to Thrift as best we can
      write_error(InternalError.new(e), protocol).tap do
        publish :internal_error, request: request, error: e, time: elapsed_ms(start_time)
      end
    end

    private

    # fetches args from a request
    def read_args(request_body, rpc, protocol)
      args_struct = args_class(service, rpc).new
      # read off the request body into a Thrift args struct
      deserialize_stream(request_body, args_struct, protocol)
      # args are named methods, but handler signatures use positional arguments;
      # convert between the two using struct_fields, which is an ordered hash.
      args_struct.struct_fields.values.map { |f| args_struct.public_send(f[:name]) }
    end

    # given any schema-defined response (success or exception), write it to the HTTP response
    def write_reply(reply, rpc, protocol)
      result_struct = result_class(service, rpc).new
      # void return types have no spot in the result struct
      unless reply.nil?
        if reply.is_a?(Thrift::Exception)
          # detect the correct exception field, if it exists, and set its value
          field = result_struct.struct_fields.values.find do |f|
            f.key?(:class) && reply.instance_of?(f[:class])
          end
          raise BadResponseError, rpc, reply unless field
          result_struct.public_send("#{field[:name]}=", reply)
        else
          # if it's not an exception, it must be the "success" value
          result_struct.success = reply
        end
      end
      # write to the response as a REPLY message
      [
        Status::REPLY,
        { Rack::CONTENT_TYPE => Encoding.content_type(protocol) },
        [serialize_buffer(result_struct, protocol)],
      ]
    end

    # Given an unexpected error (non-schema), try to write it schemaless. The
    # status code indicate to clients that an error occurred and should be
    # deserialised. The implicit schema for a non-schema exception is:
    #   struct exception { 1: string message, 2: i32 type }
    # @param exception [Errors::ServerError]
    def write_error(exception, protocol)
      # write to the response as an EXCEPTION message
      [
        Status::EXCEPTION,
        { Rack::CONTENT_TYPE => Encoding.content_type(protocol) },
        [serialize_buffer(exception.to_thrift, protocol)],
      ]
    end
  end
end
