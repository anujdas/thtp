require 'thrift'

module THTP
  # Handling of registered MIME types and protocols
  module Encoding
    BINARY = 'application/vnd.apache.thrift.binary'.freeze
    COMPACT = 'application/vnd.apache.thrift.compact'.freeze
    JSON = 'application/vnd.apache.thrift.json'.freeze

    def self.protocol(content_type)
      case content_type
      when BINARY
        Thrift::BinaryProtocol
      when COMPACT
        Thrift::CompactProtocol
      when JSON
        Thrift::JsonProtocol
      end
    end

    def self.content_type(protocol)
      # this can't be a case/when because Class !=== Class
      if protocol == Thrift::BinaryProtocol
        BINARY
      elsif protocol == Thrift::CompactProtocol
        COMPACT
      elsif protocol == Thrift::JsonProtocol
        JSON
      end
    end
  end
end
