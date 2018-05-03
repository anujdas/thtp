module ThriftHelpers
  include THTP::Utils

  def read_struct(buffer, struct, protocol)
    deserialize_buffer(buffer, struct, protocol)
  end

  def read_exception(buffer, protocol)
    read_struct(buffer, Thrift::ApplicationException.new, protocol)
  end
end

RSpec.configure do |config|
  config.include ThriftHelpers
end

RSpec::Matchers.define :be_thrift do |struct|
  match do |actual|
    expect(actual.class).to eq struct.class
    expect(actual).to match(struct)
  end
end

RSpec::Matchers.define :be_thrift_result do |service:, rpc:|
  match do |response|
    expect(response.status).to eq THTP::Status::REPLY

    protocol = THTP::Encoding.protocol(response.media_type)
    result_struct = THTP::Utils.result_class(service, rpc).new
    deserialize_buffer(response.body, result_struct, protocol)

    true
  rescue THTP::SerializationError
    false
  end
end

RSpec::Matchers.define :be_thrift_error do |error_klass = nil, message: nil|
  match do |response|
    expect(response.status).to eq THTP::Status::EXCEPTION

    protocol = THTP::Encoding.protocol(response.media_type)
    error = read_exception(response.body, protocol)

    expect(error.type).to eq(error_klass.type) unless error_klass.nil?
    expect(error.message).to match(message) unless message.nil?
    true
  rescue THTP::SerializationError
    false
  end
end
