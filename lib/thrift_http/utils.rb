require 'thrift'

require 'thrift_http/errors'

module ThriftHttp
  # Methods for interacting with generated Thrift files
  module Utils
    extend self

    # get the current time, for benchmarking purposes. monotonic time is better
    # than Time.now for this purposes. note, only works on Ruby 2.1.8+
    def get_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # useful for benchmarking. returns wall clock ms since start time
    def elapsed_ms(start_time)
      ((get_time - start_time) * 1000).round
    end

    # MyServices::Thing::ThingService -> my_services.thing.thing_service
    def service_path(service)
      service.name.underscore.tr('/', '.')
    end

    # args class is named after RPC, e.g., #get_things => Get_things_args
    def args_class(service, rpc)
      service.const_get("#{rpc.capitalize}_args")
    end

    # result class is named after RPC, e.g., #do_stuff => Do_stuff_result
    def result_class(service, rpc)
      service.const_get("#{rpc.capitalize}_result")
    end

    def deserialize(transport, struct, protocol)
      struct.read(protocol.new(transport)) # read off the stream into Thrift objects
      struct # return input object with all fields filled out
    rescue Thrift::ProtocolException, EOFError => e
      raise DeserializationError, e
    end

    def deserialize_buffer(buffer, struct, protocol)
      deserialize(Thrift::MemoryBufferTransport.new(buffer), struct, protocol)
    end

    def deserialize_stream(in_stream, struct, protocol)
      deserialize(Thrift::IOStreamTransport.new(in_stream, nil), struct, protocol)
    end

    def serialize(struct, transport, protocol)
      struct.write(protocol.new(transport))
      transport.tap(&:flush)
    rescue Thrift::ProtocolException, EOFError => e
      raise SerializationError, e
    end

    def serialize_buffer(struct, protocol)
      transport = Thrift::MemoryBufferTransport.new
      serialize(struct, transport, protocol) # write to output transport, an in-memory buffer
      transport.read(transport.available) # return serialised thrift
    end

    def serialize_stream(struct, out_stream, protocol)
      serialize(struct, Thrift::IOStreamTransport.new(nil, out_stream), protocol)
    end
  end
end
