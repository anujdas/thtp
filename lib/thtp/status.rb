module THTP
  # These HTTP status codes correspond to Thrift::MessageTypes, which tell
  # clients what kind of message body to expect.
  module Status
    # CALL is not needed because HTTP has explicit requests
    # ONEWAY is not supported in Ruby, but regardless, it has the same semantics as CALL
    REPLY = 200
    EXCEPTION = 500
  end
end
