require 'thrift'

module THTP
  # Parent class of all THTP errors
  class Error < StandardError; end

  # parent class for all errors during RPC execution;
  # serializable as a Thrift::ApplicationException
  class ServerError < Error
    # @return [Thrift::ApplicationExceptionType]
    def self.type
      Thrift::ApplicationException::UNKNOWN
    end

    # @return [Thrift::ApplicationException] a serialisable Thrift exception
    def to_thrift
      Thrift::ApplicationException.new(self.class.type, message)
    end
  end

  # parent class for all errors during RPC calls
  class ClientError < Error; end

  # Indicates an unrecognised or inappropriate RPC request format
  class BadRequestError < ServerError
    def self.type
      Thrift::ApplicationException::UNKNOWN_METHOD
    end

    def initialize
      super 'Calls must be made as POSTs to /:service/:rpc'
    end
  end

  # Indicates a well-formatted request for an RPC that does not exist
  class UnknownRpcError < ServerError
    def self.type
      Thrift::ApplicationException::WRONG_METHOD_NAME
    end

    # @param rpc [String] the RPC requested
    def initialize(rpc)
      super "Unknown RPC '#{rpc}'"
    end
  end

  # We don't recognise the response (client & server schemas don't match, or it's just invalid)
  class BadResponseError < ServerError
    def self.type
      Thrift::ApplicationException::MISSING_RESULT
    end

    def initialize(rpc, response = nil)
      super "#{rpc} failed: unknown result#{": '#{response.inspect}'" if response}"
    end
  end

  # Indicates a failure to turn a value into Thrift bytes according to schema
  class SerializationError < ServerError
    def self.type
      Thrift::ApplicationException::PROTOCOL_ERROR
    end

    # @param error [StandardError] the exception encountered while serialising
    def initialize(error)
      super friendly_message(error)
    end

    private

    def friendly_type(error)
      return :other unless error.respond_to?(:type)
      {
        1 => :invalid_data,
        2 => :negative_size,
        3 => :size_limit,
        4 => :bad_version,
        5 => :not_implemented,
        6 => :depth_limit,
      }[error.type] || :unknown
    end

    def friendly_message(error)
      "Serialization error (#{friendly_type(error)}): #{error.message}"
    end
  end

  # Indicates a failure to parse Thrift according to schema
  class DeserializationError < SerializationError
    # @param error [StandardError] the exception encountered while deserialising
    def friendly_message(error)
      "Deserialization error (#{friendly_type(error)}): #{error.message}"
    end
  end

  # Indicates that some Thrift struct failed cursory schema validation on the server
  class ServerValidationError < ServerError
    def initialize(validation_message)
      super validation_message, Thrift::ApplicationException::UNKNOWN
    end
  end

  # Indicates an uncategorised exception -- an error unrelated to Thrift,
  # somewhere in application code.
  class InternalError < ServerError
    def self.type
      Thrift::ApplicationException::INTERNAL_ERROR
    end

    # @param error [StandardError]
    def initialize(error)
      super "Internal error (#{error.class}): #{error.message}"
    end
  end

  # Indicates an unexpected and unknown message type (HTTP status)
  class UnknownMessageType < ClientError
    def self.type
      Thrift::ApplicationException::INVALID_MESSAGE_TYPE
    end

    def initialize(rpc, status, message)
      super "#{rpc} returned unknown response code #{status}: #{message}"
    end
  end

  # Indicates that the remote server could not be found
  class ServerUnreachableError < ClientError
    def initialize
      super 'Failed to open connection to host'
    end
  end

  # Indicates that RPC execution took too long
  class RpcTimeoutError < ClientError
    def initialize(rpc)
      super "Host did not respond to #{rpc} in the allotted time"
    end
  end

  # Indicates that some Thrift struct failed cursory schema validation on the client
  class ClientValidationError < ClientError; end
end
