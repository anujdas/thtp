require 'forwardable'
require 'rack'
require 'thrift'

require 'thrift_http/encoding'
require 'thrift_http/errors'
require 'thrift_http/middleware_stack'
require 'thrift_http/pub_sub'
require 'thrift_http/routing'
require 'thrift_http/status'
require 'thrift_http/utils'

module ThriftHttp
  # An HTTP implementation of Thrift-RPC
  # @abstract Subclass and call `.set_service` to configure for usage
  class Server
    extend Forwardable
    extend SingleForwardable

    include Routing
    include PubSub
    include Utils

    class << self
      # @param service [Thrift::Service] The service class handled by this server
      # @param handlers [Object,Array<Object>] The object(s) handling RPC requests
      def set_service(service, handlers: [])
        @service = service
        @handler = MiddlewareStack.new(service, handlers)
      end

      # @yield [ThriftHttp::Server] The class itself, for middleware/subscriber attachment
      def configure
        raise 'Configure using .set_service before using' unless @service
        yield self if block_given?
      end

      def call(rack_env)
        request = Rack::Request.new(rack_env)
        response = Rack::Response.new([], 404) # default response is not-found
        if (route = match_route(request))
          new(request, response, route.path_params).instance_eval(&route.handler)
        end
        response.finish
      end

      def service
        raise 'Configure using .set_service before using' unless @service
        @service
      end

      def handler
        raise 'Configure using .set_service before using' unless @handler
        @handler
      end
    end

    def_single_delegators :handler, :use
    def_instance_delegators :'self.class', :service, :handler, :publish

    attr_reader :request, :response, :path_params

    def initialize(request, response, path_params = nil)
      @request = request # Rack::Request
      @response = response # Rack::Response
      @path_params = path_params || {} # Hash<Symbol, String>: captures from path
    end

    ### Routes

    post '/:service_name/:rpc/?' do
      start_time = get_time
      # extract path params and verify routing
      service_name, rpc = path_params.values_at(:service_name, :rpc)
      raise BadRequestError unless service_name == service_path(service)
      raise UnknownRpcError, rpc unless handler.respond_to?(rpc)
      # read, perform, write
      args = read_args(rpc)
      result = handler.public_send(rpc, *args)
      write_reply(rpc, result)
      # get out the stats
      publish :rpc_success,
              request: request, rpc: rpc, args: args, result: result, time: elapsed_ms(start_time)
    rescue Thrift::Exception => e # known schema-defined Thrift errors
      write_reply(rpc, e)
      publish :rpc_exception,
              request: request, rpc: rpc, args: args, exception: e, time: elapsed_ms(start_time)
    rescue ServerError => e # known server/communication errors
      write_error(e)
      publish :rpc_error,
              request: request, rpc: rpc, args: args, error: e, time: elapsed_ms(start_time)
    rescue => e # a non-Thrift exception occurred; translate to Thrift as best we can
      write_error(InternalError.new(e))
      publish :internal_error, request: request, error: e, time: elapsed_ms(start_time)
    end

    get '/health/?' do
      response.write 'Everything is OK'.freeze
      response.headers[Rack::CONTENT_TYPE] = 'text/plain'.freeze
      response.status = 200
    end

    private

    # use official MIME types to determine proper protocol. default to
    # CompactProtocol because we need one with which to send back errors.
    def protocol
      Encoding.protocol(request.media_type) || Thrift::CompactProtocol
    end

    # fetches args from a request
    def read_args(rpc)
      # read off the request body into a Thrift args struct
      args = deserialize(args_class(service, rpc).new, request.body.read, protocol)
      # args are named methods, but handler signatures use positional arguments;
      # convert between the two using struct_fields, which is an ordered hash.
      args.struct_fields.values.map { |f| args.public_send(f[:name]) }
    end

    # given any schema-defined response (success or exception), write it to the HTTP response
    def write_reply(rpc, reply)
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
      response.write(serialize(result_struct, protocol))
      response.headers[Rack::CONTENT_TYPE] = Encoding.content_type(protocol)
      response.status = Status::REPLY
    end

    # Given an unexpected error (non-schema), try to write it schemaless. The
    # status code indicate to clients that an error occurred and should be
    # deserialised. The implicit schema for a non-schema exception is:
    #   struct exception { 1: string message, 2: i32 type }
    # @param exception [Errors::ServerError]
    def write_error(exception)
      # write to the response as an EXCEPTION message
      response.write(serialize(exception.to_thrift, protocol))
      response.headers[Rack::CONTENT_TYPE] = Encoding.content_type(protocol)
      response.status = Status::EXCEPTION
    end
  end
end
