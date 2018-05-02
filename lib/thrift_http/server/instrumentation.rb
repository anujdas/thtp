# frozen_string_literal: true

require 'thrift'
require 'thrift_http/errors'
require 'thrift_http/utils'

module ThriftHttp
  class Server
    module Instrumentation
      # A ThriftHttp::Server Server subscriber for RPC metrics reporting
      class Metrics
        INBOUND_RPC_STAT = 'rpc.incoming'

        SUCCESS_TAG = 'rpc.status:success' # everything is ok
        EXCEPTION_TAG = 'rpc.status:exception' # schema-defined (expected) exception
        ERROR_TAG = 'rpc.status:error' # unexpected error
        INTERNAL_ERROR_TAG = 'rpc.status:internal_error'

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
      class Logging
        include Utils

        def initialize(logger, backtrace_lines: 5)
          @logger = logger
          @backtrace_lines = backtrace_lines
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
              http: http_request_to_hash(request),
              request: args_to_hash(args),
              result: result_to_hash(result),
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
              http: http_request_to_hash(request),
              request: args_to_hash(args),
              exception: result_to_hash(exception),
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
              http: http_request_to_hash(request),
              request: args_to_hash(args),
              error: error_to_hash(error),
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
              http: http_request_to_hash(request),
              internal_error: error_to_hash(error),
              elapsed_ms: time,
            }
          end
        end

        private

        def http_request_to_hash(rack_request)
          {
            user_agent: rack_request.user_agent,
            content_type: rack_request.content_type,
            verb: rack_request.request_method,
            path: rack_request.path_info,
            ssl: rack_request.ssl?,
          }
        end

        def args_to_hash(rpc_args)
          jsonify(rpc_args)
        end

        # converts all possible Thrift result types to JSON, inferring types
        # from collections, with the intent of producing ELK-compatible output
        # (i.e., no multiple-type-mapped fields)
        def result_to_hash(result)
          case result
          when nil
            nil # nulls are ok in ELK land
          when Array
            { list: { result.first.class.name => jsonify(result) } }
          when Set
            { set: { result.first.class.name => jsonify(result) } }
          when Hash
            ktype, vtype = result.first.map { |obj| obj.class.name }
            { hash: { ktype => { vtype => jsonify(result) } } }
          else # primitives
            { result.class.name => jsonify(result) }
          end
        end

        # converts non-schema errors to an ELK-compatible format (JSON-serialisable hash)
        def error_to_hash(error)
          trace = error.backtrace.first(@backtrace_lines)
          { error.class.name => jsonify(error).merge(backtrace: trace) }
        end
      end

      # Captures exceptions to Sentry
      class Sentry
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
          @raven.capture_exception(exception, **rpc_context(request, rpc, args))
        end

        # An unknown error occurred
        # @param request [Rack::Request] The inbound HTTP request
        # @param error [Exception] The to-be-serialized exception
        # @param time [Integer] Milliseconds of execution wall time
        def internal_error(request:, error:, time:)
          @raven.capture_exception(exception, **http_context(request))
        end

        private

        # subclass and override if desired
        # @param rack_request [Rack::Request] The inbound HTTP request
        def http_context(rack_request)
          {
            user: { ip: rack_request.ip, user_agent: rack_request.user_agent },
            extra: {},
          }
        end

        # subclass and override if desired
        # @param rack_request [Rack::Request] The inbound HTTP request
        # @param rpc [Symbol] The name of the RPC
        # @param args [Thrift::Struct] The deserialized thrift args
        def rpc_context(rack_request, rpc, args) # rubocop:disable Lint/UnusedMethodArgument
          http_context(rack_request).tap do |context|
            context[:extra].merge!(rpc: rpc)
          end
        end
      end
    end
  end
end
