require 'thrift_http/errors'

module ThriftHttp
  module Middleware
    # Raise Thrift validation issues as their own detectable error type, rather
    # than just ProtocolException.
    class SchemaValidation
      def initialize(app, error: ClientValidationError)
        @app = app
        @error_class = error
      end

      # Raises a ValidationError if any part of the request or response did not
      # match the schema
      def call(rpc, *rpc_args, **rpc_opts)
        validate(rpc_args)
        @app.call(rpc, *rpc_args, **rpc_opts).tap { |resp| validate(resp) }
      end

      private

      # @param structs [Object] any Thrift value -- struct, primitive, or a collection thereof
      # @raise [ThriftHttp::ValidationError] if any deviation from schema was detected
      # @return [nil] if no problems were detected; note that this does not include type checks
      def validate(structs)
        # handle anything -- Struct, Union, List, Set, Map, primitives...
        Array(structs).flatten.each do |struct|
          # only Structs/Unions can be validated (see Thrift.type_checking for another option)
          next unless struct.is_a?(Thrift::Struct_Union)
          # raises a ProtocolException if this specific struct is invalid
          struct.validate
          # recursively validate all fields except unset union fields
          struct.struct_fields.each_value do |f|
            next if struct.is_a?(Thrift::Union) && struct.get_set_field != f[:name].to_sym
            validate(struct.send(f[:name]))
          end
        rescue Thrift::ProtocolException => e
          raise @error_class, "#{struct.class}: #{e.message}"
        end
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
        require 'active_record'
        @app = app
      end

      def call(rpc, *rpc_args_and_opts)
        ActiveRecord::Base.connection_pool.with_connection { @app.call(rpc, *rpc_args_and_opts) }
      end
    end
  end
end
