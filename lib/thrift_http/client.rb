require 'forwardable'
require 'httpclient'
require 'thrift'

require 'thrift_http/encoding'
require 'thrift_http/errors'
require 'thrift_http/middleware_stack'
require 'thrift_http/status'
require 'thrift_http/utils'

module ThriftHttp
  # A thrift-over-HTTP client library implementing persistent connections and
  # extensibility via middlewares
  # @abstract Subclass and call `.set_service` to configure for usage
  class Client
    extend Forwardable
    include Utils

    class << self
      def set_service(service, protocol: Thrift::CompactProtocol,
                      host: '0.0.0.0'.freeze, port: nil, ssl: false,
                      open_timeout: 0.5, rpc_timeout: 15, keep_alive: 15)
        @service = service
        @protocol = protocol

        # set up HTTP connection -- note, this is persistent per-thread
        uri_class = ssl ? URI::HTTPS : URI::HTTP
        base_url = uri_class.build(host: host, port: port, path: "/#{Utils.service_path(service)}/")
        @connection = HTTPClient.new(
          base_url: base_url,
          agent_name: user_agent,
          default_header: default_headers,
        ) do |client|
          client.connect_timeout = open_timeout # seconds
          client.receive_timeout = rpc_timeout # seconds
          client.keep_alive_timeout = keep_alive # seconds
          client.ssl_config.set_default_paths # use system certs rather than builtins
          client.transparent_gzip_decompression = true
        end

        # allow middleware insertion for purposes such as instrumentation or validation
        @stack = MiddlewareStack.new(service, new)
        @stack.rpcs.each do |rpc|
          define_singleton_method(rpc) { |*rpc_args_and_opts| @stack.send(rpc, *rpc_args_and_opts) }
          define_method(rpc) { |*rpc_args| post_rpc(rpc, *rpc_args) }
        end
      end

      # @yield [ThriftHttp::Client] The class itself, for middleware attachment
      def configure
        raise 'Configure using .set_service before using' unless @service
        yield @stack if block_given?
      end

      def service
        raise 'Configure using .set_service before using' unless @service
        @service
      end

      def protocol
        raise 'Configure using .set_service before using' unless @protocol
        @protocol
      end

      def connection
        raise 'Configure using .set_service before using' unless @connection
        @connection
      end

      private

      # override if desired
      def user_agent
        name
      end

      # override if desired
      def default_headers
        { 'Content-Type'.freeze => Encoding.content_type(protocol) }
      end
    end

    private

    SUCCESS_FIELD = 'success'.freeze # the Thrift result field that's set if everything went fine

    def_instance_delegators :'self.class', :service, :connection

    def post_rpc(rpc, *args)
      # send request over persistent HTTP connection
      response = connection.post(URI(rpc.to_s), body: write_call(rpc, args))
      # interpret HTTP status code to determine message type and deserialise appropriately
      protocol = Encoding.protocol(response.contenttype) || self.class.protocol
      return read_reply(rpc, response.body, protocol) if response.status == Status::REPLY
      return read_exception(response.body, protocol) if response.status == Status::EXCEPTION
      # if the HTTP status code was unrecognised, report back
      raise UnknownMessageType, rpc, response.status, response.body
    rescue Errno::ECONNREFUSED, HTTPClient::ConnectTimeoutError
      raise ServerUnreachableError
    rescue HTTPClient::ReceiveTimeoutError
      raise RpcTimeoutError, rpc
    end

    def write_call(rpc, args)
      args_struct = args_class(service, rpc).new
      # args are named methods, but RPC signatures use positional arguments;
      # convert between the two using struct_fields, which is an ordered hash.
      args_struct.struct_fields.values.zip(args).each do |field, val|
        args_struct.public_send("#{field[:name]}=", val)
      end
      # serialise and return bytestring
      serialize(args_struct, self.class.protocol)
    end

    def read_reply(rpc, reply, protocol)
      # deserialise reply into result struct
      result = deserialize(result_class(service, rpc).new, reply, protocol)
      # results have at most one field set; find it and return/raise it
      result.struct_fields.each_value do |field|
        reply = result.public_send(field[:name])
        next if reply.nil? # this isn't the set field, keep looking
        return reply if field[:name] == SUCCESS_FIELD # 'success' is special and means no worries
        raise reply # any other set field must be an exception
      end
      # if no field is set and there's no `success` field, the RPC returned `void``
      return nil unless result.respond_to?(:success)
      # otherwise, we don't recognise the response (our schema is out of date, or it's invalid)
      raise BadResponseError, rpc
    end

    def read_exception(exception, protocol)
      raise deserialize(Thrift::ApplicationException.new, exception, protocol)
    end
  end
end
