# frozen_string_literal: true

require 'connection_pool'
require 'patron'
require 'thrift'

require 'thtp/encoding'
require 'thtp/errors'
require 'thtp/middleware_stack'
require 'thtp/status'
require 'thtp/utils'

require 'thtp/client/instrumentation'
require 'thtp/client/middleware'

module THTP
  # A thrift-over-HTTP client library implementing persistent connections and
  # extensibility via middlewares
  class Client
    include Utils

    # RPC-over-HTTP protocol implementation and executor
    class Dispatcher
      include Utils

      SUCCESS_FIELD = 'success' # the Thrift result field that's set if everything went fine

      # @param service [Class] The Thrift service whose schema to use for de/serialisation
      # @parma connection [ConnectionPool<Patron::Session>] The configured HTTP client pool
      # @param protocol [Thrift::BaseProtocol] The default protocol with which to serialise
      def initialize(service, connection, protocol)
        @service = service
        @connection = connection
        @protocol = protocol
        # define RPC proxy methods on this instance
        extract_rpcs(service).each do |rpc|
          define_singleton_method(rpc) { |*rpc_args| post_rpc(rpc, *rpc_args) }
        end
      end

      private

      def post_rpc(rpc, *args)
        # send request over persistent HTTP connection
        response = @connection.with { |c| c.post(rpc, write_call(rpc, args)) }
        # interpret HTTP status code to determine message type and deserialise appropriately
        protocol = Encoding.protocol(response.headers['Content-Type']) || @protocol
        return read_reply(rpc, response.body, protocol) if response.status == Status::REPLY
        return read_exception(response.body, protocol) if response.status == Status::EXCEPTION
        # if the HTTP status code was unrecognised, report back
        raise UnknownMessageType, rpc, response.status, response.body
      rescue Patron::TimeoutError, Timeout::Error
        raise RpcTimeoutError, rpc
      rescue Patron::Error
        raise ServerUnreachableError
      end

      def write_call(rpc, args)
        # args are named methods, but RPC signatures use positional arguments;
        # convert between the two using struct_fields, which is an ordered hash.
        args_struct = args_class(@service, rpc).new
        args_struct.struct_fields.values.zip(args).each do |field, val|
          args_struct.public_send("#{field[:name]}=", val)
        end
        # serialise and return bytestring
        serialize_buffer(args_struct, @protocol)
      rescue Thrift::TypeError => e
        raise ClientValidationError, e.message
      end

      def read_reply(rpc, reply, protocol)
        # deserialise reply into result struct
        result_struct = result_class(@service, rpc).new
        deserialize_buffer(reply, result_struct, protocol)
        # results have at most one field set; find it and return/raise it
        result_struct.struct_fields.each_value do |field|
          reply = result_struct.public_send(field[:name])
          next if reply.nil? # this isn't the set field, keep looking
          return reply if field[:name] == SUCCESS_FIELD # 'success' is special and means no worries
          raise reply # any other set field must be an exception
        end
        # if no field is set and there's no `success` field, the RPC returned `void``
        return nil unless result_struct.respond_to?(:success)
        # otherwise, we don't recognise the response (our schema is out of date, or it's invalid)
        raise BadResponseError, rpc
      end

      def read_exception(exception, protocol)
        raise deserialize_buffer(exception, Thrift::ApplicationException.new, protocol)
      end
    end

    ###

    # @param service [Class] The Thrift service whose schema to use for de/serialisation
    def initialize(service, protocol: Thrift::CompactProtocol,
                   host: '0.0.0.0', port: nil, ssl: false,
                   open_timeout: 1, rpc_timeout: 15,
                   pool_size: 5, pool_timeout: 5)
      uri_class = ssl ? URI::HTTPS : URI::HTTP
      # set up HTTP connections in a thread-safe pool
      connection = ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        Patron::Session.new(
          base_url: uri_class.build(host: host, port: port, path: "/#{canonical_name(service)}/"),
          connect_timeout: open_timeout,
          timeout: rpc_timeout,
          headers: {
            'Content-Type' => Encoding.content_type(protocol),
            'User-Agent' => self.class.name,
          },
        )
      end
      # allow middleware insertion for purposes such as instrumentation or validation
      @stack = MiddlewareStack.new(service, Dispatcher.new(service, connection, protocol))
      extract_rpcs(service).each { |rpc| define_singleton_method(rpc, &@stack.method(rpc)) }
    end

    # delegate to RPC dispatcher stack
    def use(middleware_class, *middleware_args)
      @stack.use(middleware_class, *middleware_args)
    end
  end
end
