require 'thrift'
require 'thrift_http/errors'

module ThriftHttp
  class Client
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
          raise ClientValidationError, e.message
        end
      end
    end
  end
end
