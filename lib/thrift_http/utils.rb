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

    def serialize(struct, protocol)
      transport = Thrift::MemoryBufferTransport.new
      struct.write(protocol.new(transport)) # write to output transport, an in-memory byte buffer
      transport.read(transport.available) # return serialised thrift
    rescue Thrift::ProtocolException, EOFError => e
      raise SerializationError, e
    end

    def deserialize(struct, buffer, protocol)
      transport = Thrift::MemoryBufferTransport.new(buffer)
      struct.read(protocol.new(transport)) # read off the buffer into Thrift objects
      struct # return input object with all fields filled out
    rescue Thrift::ProtocolException, EOFError => e
      raise DeserializationError, e
    end
  end
end
