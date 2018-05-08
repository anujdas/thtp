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

    THRIFT_IDENT = /[a-zA-Z_][\w.]*/
    RPC_ROUTE = %r{^/(?<service>#{THRIFT_IDENT})/(?<rpc>#{THRIFT_IDENT})/?}

    attr_reader :service

    # @param app [Object?] The Rack application underneath, if used as middleware
    # @param service [Thrift::Service] The service class handled by this server
    # @param handlers [Object,Array<Object>] The object(s) handling RPC requests
    def initialize(app = NullRoute.new, service:, handlers: [])
      @app = app
      @service = service
      @handler = MiddlewareStack.new(service, handlers)
    end

    # delegate to RPC handler stack
    def use(middleware_class, *middleware_args)
      @handler.use(middleware_class, *middleware_args)
    end

    # Rack implementation entrypoint
    def call(env)
      start_time = get_time
      set_rpc_attrs(env)
      # verify routing
      return @app.call(env) unless canonical_name(service) == env['thtp.service']
      # get RPC name from route
      rpc = env['thtp.rpc']
      raise UnknownRpcError, rpc unless @handler.respond_to?(rpc)
      # read, perform, write
      request = Rack::Request.new(env)
      protocol = env['thtp.protocol']
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

    def set_rpc_attrs(env)
      content_type = env['HTTP_CONTENT_TYPE'].split(';').first
      env['thtp.protocol'] = Encoding.protocol(content_type) || Thrift::CompactProtocol

      return unless env['REQUEST_METHOD'] == 'POST' && (match = RPC_ROUTE.match(env['PATH_INFO']))
      env['thtp.service'] = decanonicalise(match[:service])
      env['thtp.rpc'] = match[:rpc]
    end

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
        # test whether reply is part of RPC schmea definition
        field = result_struct.struct_fields.values.find { |f| reply.instance_of?(f[:class]) }
        raise BadResponseError, rpc, reply unless field
        # if yes, return a result with the appropriate error field set
        result_struct.public_send("#{field[:name]}=", reply)
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
