module ThriftHelpers
  include THTP::Utils

  def read_struct(buffer, struct, protocol)
    deserialize_buffer(buffer, struct, protocol)
  end

  def read_exception(buffer, protocol)
    read_struct(buffer, Thrift::ApplicationException.new, protocol)
  end

  def read_result_response(response, service, rpc)
    protocol = THTP::Encoding.protocol(response.media_type)
    result_struct = THTP::Utils.result_class(service, rpc).new
    read_struct(response.body, result_struct, protocol)
  end

  def read_exception_response(response)
    protocol = THTP::Encoding.protocol(response.media_type)
    read_exception(response.body, protocol)
  end

  def get_result_type(result_struct)
    result_struct.struct_fields.each_value do |field|
      return field[:name] unless result_struct.send(field[:name]).nil?
    end
  end

  def get_result_response(response, service, rpc)
    result = read_result_response(response, service, rpc)
    field = get_result_type(result)
    return result.send(field) if field
    return nil unless result.respond_to?(:success)
    raise THTP::BadResponseError, rpc
  end
end

RSpec.configure do |config|
  config.include ThriftHelpers
end

RSpec::Matchers.define :be_thrift_struct do |klass, attrs|
  match do |struct|
    expect(struct).to be_a klass
    expect(struct).to have_attributes(attrs) unless attrs.nil?
  end
end

RSpec::Matchers.define :be_thrift_result_response do |service, rpc|
  match do |response|
    return false if service.nil? || rpc.nil?
    return false if response.status != THTP::Status::REPLY
    read_result_response(response, service, rpc)
    true
  rescue THTP::SerializationError
    false
  end

  failure_message do |response|
    return 'service and rpc must be specified' if service.nil? || rpc.nil?

    read_result_response(response, service, rpc)

    if response.status != THTP::Status::REPLY
      "expected HTTP status #{THTP::Status::REPLY}, but was #{response.status}"
    end
  rescue THTP::SerializationError
    'expected a Thrift ApplicationException, but deserialisation failed'
  end
end

RSpec::Matchers.define :be_a_thrift_success_response do |service, rpc, klass, attrs|
  match do |response|
    return false if service.nil? || rpc.nil?
    return false if response.status != THTP::Status::REPLY
    result = read_result_response(response, service, rpc)
    result_type = get_result_type(result)
    return false unless result_type.nil? || result_type == 'success'
    expect(result.success).to be_thrift_struct(klass, attrs) if klass && result_type
    true
  rescue THTP::SerializationError, Thrift::BadResponseError
    false
  end

  failure_message do |response|
    return 'service and rpc must be specified' if service.nil? || rpc.nil?

    result = read_result_response(response, service, rpc)
    result_type = get_result_type(result)

    if response.status != THTP::Status::REPLY
      "expected HTTP status #{THTP::Status::REPLY}, but was #{response.status}"
    elsif !result_type.nil? && result_type != 'success'
      "expected successful Thrift result, but was #{result_type} instead"
    elsif klass && result_type
      expect(result.success).to be_thrift_struct(klass, attrs)
    end
  rescue THTP::SerializationError
    'expected a Thrift ApplicationException, but deserialisation failed'
  rescue Thrift::BadResponseError
    'expected a result, but no result field was set'
  end
end

RSpec::Matchers.define :be_a_thrift_exception_response do |service, rpc, klass, attrs|
  match do |response|
    return false if service.nil? || rpc.nil?
    return false if response.status != THTP::Status::REPLY
    result = read_result_response(response, service, rpc)
    result_type = get_result_type(result)
    return false if result_type.nil? || result_type == 'success'
    expect(result.send(result_type)).to be_thrift_struct(klass, attrs) if klass
    true
  rescue THTP::SerializationError, Thrift::BadResponseError
    false
  end

  failure_message do |response|
    return 'service and rpc must be specified' if service.nil? || rpc.nil?

    result = read_result_response(response, service, rpc)
    result_type = get_result_type(result)

    if response.status != THTP::Status::REPLY
      "expected HTTP status #{THTP::Status::REPLY}, but was #{response.status}"
    elsif result_type.nil? || result_type == 'success'
      "expected Thrift exception, but was #{result_type} instead"
    elsif klass
      expect(result.send(result_type)).to be_thrift_struct(klass, attrs)
    end
  rescue THTP::SerializationError
    'expected a Thrift ApplicationException, but deserialisation failed'
  rescue Thrift::BadResponseError
    'expected a result, but no result field was set'
  end
end

RSpec::Matchers.define :be_thrift_error_response do |error_klass, message|
  match do |response|
    error = read_exception_response(response)

    return false if response.status != THTP::Status::EXCEPTION
    return false if !error_klass.nil? && error.type != error_klass.type
    expect(error.message).to match(message) unless message.nil?
    true
  rescue THTP::SerializationError
    false
  end

  failure_message do |response|
    error = read_exception_response(response)

    if response.status != THTP::Status::EXCEPTION
      "expected HTTP status #{THTP::Status::EXCEPTION}, but was #{response.status}"
    elsif !error_klass.nil? && error.type != error_klass.type
      "expected ApplicationExceptionType #{error_klass.type}, but was #{error.type}"
    elsif !message.nil?
      expect(error.message).to match(message)
    end
  rescue THTP::SerializationError
    'expected a Thrift ApplicationException, but deserialisation failed'
  end
end
