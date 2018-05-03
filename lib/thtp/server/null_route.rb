require 'rack'
require 'thrift'

require 'thtp/encoding'
require 'thtp/errors'
require 'thtp/status'
require 'thtp/utils'

module THTP
  # A THTP middleware stack terminator, telling clients they've done
  # something wrong if their requests weren't captured by a running server
  class NullRoute
    # if a request makes it here, it's bad; tell the caller what it should have done
    def call(env)
      # default to CompactProtocol because we need a protocol with which to send back errors
      protocol = Encoding.protocol(Rack::Request.new(env).media_type) || Thrift::CompactProtocol
      headers = { Rack::CONTENT_TYPE => Encoding.content_type(protocol) }
      body = Utils.serialize_buffer(BadRequestError.new.to_thrift, protocol)
      [Status::EXCEPTION, headers, [body]]
    end
  end
end
