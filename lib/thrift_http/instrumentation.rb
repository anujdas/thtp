# frozen_string_literal: true

require 'thrift_http/utils'

module ThriftHttp
  module Instrumentation
    INBOUND_RPC_STAT = 'rpc.incoming'
    OUTBOUND_RPC_STAT = 'rpc.incoming'

    SUCCESS_TAG = 'rpc.status:success' # everything is ok
    EXCEPTION_TAG = 'rpc.status:exception' # schema-defined (expected) exception
    ERROR_TAG = 'rpc.status:error' # unexpected error
    INTERNAL_ERROR_TAG = 'rpc.status:internal_error'

    # Automagic instrumentation for all outbound RPCs as a ThriftHttp::Client middleware
    class ClientMetrics
      def initialize(app, from:, to:, statsd:)
        unless defined?(Datadog::Statsd) && statsd.is_a?(Datadog::Statsd)
          raise ArgumentError, "Only dogstatsd is supported, not #{statsd.class.name}"
        end
        @app = app
        @statsd = statsd
        @base_tags = ["rpc.from:#{from}", "rpc.to:#{to}"]
      end

      def call(rpc, *rpc_args, **rpc_opts)
        start = Utils.get_time
        status_tag = SUCCESS_TAG
        error_tag = nil
        @app.call(rpc, *rpc_args, **rpc_opts)
      rescue Thrift::Exception => e
        status_tag = EXCEPTION_TAG
        error_tag = "rpc.exception:#{e.class.name.underscore}"
        raise
      rescue => e
        status_tag = ERROR_TAG
        error_tag = "rpc.error:#{e.class.name.underscore}"
        raise
      ensure
        tags = ["rpc:#{rpc}", status_tag, error_tag, *@base_tags].compact
        @statsd.timing(OUTBOUND_RPC_STAT, Utils.elapsed_ms(start), tags: tags)
      end
    end

    # A ThriftHttp::Server Server subscriber for RPC metrics reporting
    class ServerMetrics
      def initialize(statsd)
        unless defined?(Datadog::Statsd) && statsd.is_a?(Datadog::Statsd)
          raise ArgumentError, 'Only dogstatsd is supported'
        end
        @statsd = statsd
      end

      # Everything went according to plan
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param result [Thrift::Struct] The to-be-serialized thrift response
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_success(request:, rpc:, args:, result:, time:)
        tags = ["rpc:#{rpc}", SUCCESS_TAG]
        @statsd.timing(INBOUND_RPC_STAT, time, tags: tags)
      end

      # Handler raised an exception defined in the schema
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param exception [Thrift::Struct] The to-be-serialized thrift exception
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_exception(request:, rpc:, args:, exception:, time:)
        tags = ["rpc:#{rpc}", EXCEPTION_TAG, "rpc.error:#{exception.class.name.underscore}"]
        @statsd.timing(INBOUND_RPC_STAT, time, tags: tags)
      end

      # Handler raised an unexpected error
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param error [ThriftHttp::ServerError] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_error(request:, rpc:, args:, error:, time:)
        tags = ["rpc:#{rpc}", ERROR_TAG, "rpc.error:#{error.class.name.underscore}"]
        @statsd.timing(INBOUND_RPC_STAT, time, tags: tags)
      end

      # An unknown error occurred
      # @param request [Rack::Request] The inbound HTTP request
      # @param error [Exception] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def internal_error(request:, error:, time:)
        tags = [INTERNAL_ERROR_TAG, "rpc.error:#{error.class.name.underscore}"]
        @statsd.timing(INBOUND_RPC_STAT, time, tags: tags)
      end
    end

    # A ThriftHttp::Server subscriber for RPC logging and exception recording
    class ServerLogging
      BACKTRACE_LINES = 5 # lines to include in logs -- full stacktrace goes to error_handler

      def initialize(logger)
        @logger = logger
      end

      # Everything went according to plan
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param result [Thrift::Struct] The to-be-serialized thrift response
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_success(request:, rpc:, args:, result:, time:)
        @logger.info :rpc do
          {
            rpc: rpc,
            http: request_to_hash(request),
            request: args_to_hash(args),
            result: response_to_hash(result),
            elapsed_ms: time,
          }
        end
      end

      # Handler raised an exception defined in the schema
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param exception [Thrift::Struct] The to-be-serialized thrift exception
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_exception(request:, rpc:, args:, exception:, time:)
        @logger.info :rpc do
          {
            rpc: rpc,
            http: request_to_hash(request),
            request: args_to_hash(args),
            exception: exception_to_hash(exception),
            elapsed_ms: time,
          }
        end
      end

      # Handler raised an unexpected error
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param error [ThriftHttp::ServerError] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_error(request:, rpc:, args:, error:, time:)
        @logger.error :rpc do
          {
            rpc: rpc,
            http: request_to_hash(request),
            request: args_to_hash(args),
            error: exception_to_hash(exception),
            elapsed_ms: time,
          }
        end
      end

      # An unknown error occurred
      # @param request [Rack::Request] The inbound HTTP request
      # @param error [Exception] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def internal_error(request:, error:, time:)
        @logger.error :server do
          {
            http: request_to_hash(request),
            internal_error: exception_to_hash(error, backtrace: true),
            elapsed_ms: time,
          }
        end
      end

      private

      def request_to_hash(rack_request)
        {
          user_agent: rack_request.user_agent,
          content_type: rack_request.content_type,
          verb: rack_request.request_method,
          path: rack_request.path_info,
          ssl: rack_request.ssl?,
        }
      end

      def args_to_hash(rpc_args)
        rpc_args.as_json
      end

      # converts all possible Thrift result types to JSON, inferring types from
      # collections, with the intent of producing ELK-compatible output (i.e.,
      # no multiple-type-mapped fields)
      def response_to_hash(response)
        case response
        when nil
          nil # nulls are ok in ELK land
        when Thrift::Struct_Union
          response.as_json # structs and unions are both json-able
        when Array
          { list: { response.first.class.name => response.as_json } }
        when Set
          { set: { response.first.class.name => response.as_json } }
        when Hash
          ktype, vtype = response.first.map { |obj| obj.class.name }
          { hash: { ktype => { vtype => response.as_json } } }
        else
          { primitive: { response.class.name => response } }
        end
      end

      def exception_to_hash(exception, backtrace: false)
        hash = { type: exception.class.name, message: exception.message, repr: exception.inspect }
        hash[:backtrace] = exception.backtrace.first(BACKTRACE_LINES) if backtrace
        hash
      end
    end

    # Captures exceptions to Sentry
    class ServerSentry
      # @param raven [Raven] A Sentry client instance, or something that acts like one
      def initialize(raven)
        @raven = raven
      end

      # Handler raised an unexpected error
      # @param request [Rack::Request] The inbound HTTP request
      # @param rpc [Symbol] The name of the RPC
      # @param args [Thrift::Struct] The deserialized thrift args
      # @param error [ThriftHttp::ServerError] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def rpc_error(request:, rpc:, args:, error:, time:)
        user_context = { ip: request.ip, user_agent: request.user_agent }
        request_context = { rpc: rpc }
        @raven.capture_exception(exception, user: user_context, extra: request_context)
      end

      # An unknown error occurred
      # @param request [Rack::Request] The inbound HTTP request
      # @param error [Exception] The to-be-serialized exception
      # @param time [Integer] Milliseconds of execution wall time
      def internal_error(request:, error:, time:)
        @raven.capture_exception(error)
      end
    end
  end
end
