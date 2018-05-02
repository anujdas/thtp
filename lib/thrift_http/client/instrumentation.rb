# frozen_string_literal: true

require 'thrift_http/utils'

module ThriftHttp
  class Client
    module Instrumentation
      # Automagic instrumentation for all outbound RPCs as a ThriftHttp::Client middleware
      class Metrics
        OUTBOUND_RPC_STAT = 'rpc.outgoing'

        SUCCESS_TAG = 'rpc.status:success' # everything is ok
        EXCEPTION_TAG = 'rpc.status:exception' # schema-defined (expected) exception
        ERROR_TAG = 'rpc.status:error' # unexpected error
        INTERNAL_ERROR_TAG = 'rpc.status:internal_error'

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
    end
  end
end
