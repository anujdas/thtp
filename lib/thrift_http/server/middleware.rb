require 'thrift'
require 'thrift_http/errors'

module ThriftHttp
  class Server
    module Middleware
      # Raise Thrift validation issues as their own detectable error type, rather
      # than just ProtocolException.
      class SchemaValidation
        def initialize(app)
          require 'thrift/validator' # if you don't have it, you'll need it
          @app = app
          @validator = Thrift::Validator.new
        end

        # Raises a ValidationError if any part of the request or response did not
        # match the schema
        def call(rpc, *rpc_args, **rpc_opts)
          @validator.validate(rpc_args)
          @app.call(rpc, *rpc_args, **rpc_opts).tap { |resp| @validator.validate(resp) }
        rescue Thrift::ProtocolException => e
          raise ServerValidationError, e.message
        end
      end

      # Performs explicit rather than implicit AR connection management to ensure
      # we don't run out of SQL connections. Note that this approach is
      # suboptimal from a contention standpoint (better to check out once per
      # thread), but that sync time should be irrelevant if we size our pool
      # correctly, which we do. It is also suboptimal if we have any handler
      # methods that do not hit the database at all, but that's unlikely.
      #
      # For more details, check out (get it?):
      # https://bibwild.wordpress.com/2014/07/17/activerecord-concurrency-in-rails4-avoid-leaked-connections/
      #
      # This is probably only useful on servers.
      class ActiveRecordPool
        def initialize(app)
          require 'active_record' # if you don't have it, why do you want this?
          @app = app
        end

        def call(rpc, *rpc_args_and_opts)
          ActiveRecord::Base.connection_pool.with_connection { @app.call(rpc, *rpc_args_and_opts) }
        end
      end
    end
  end
end
