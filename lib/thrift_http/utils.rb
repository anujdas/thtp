require 'thrift'

require 'thrift_http/errors'

module ThriftHttp
  # Methods for interacting with generated Thrift files
  module Utils
    extend self

    ### Timing

    # get the current time, for benchmarking purposes. monotonic time is better
    # than Time.now for this purposes. note, only works on Ruby 2.1.8+
    def get_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # useful for benchmarking. returns wall clock ms since start time
    def elapsed_ms(start_time)
      ((get_time - start_time) * 1000).round
    end

    ### Thrift definition hacks

    # @return array<Symbol> for a given thrift Service using reflection
    #   because the Thrift compiler's generated definitions do not lend
    #   themselves to external use
    def extract_rpcs(thrift_service)
      # it's really the Processor we want (the Client would work too)
      root = thrift_service < Thrift::Processor ? thrift_service : thrift_service::Processor
      # get all candidate classes that may contribute RPCs to this service
      root.ancestors.flat_map do |klass|
        next [] unless klass < Thrift::Processor
        klass.instance_methods(false).
          select { |method_name| method_name =~ /^process_/ }.
          map { |method_name| method_name.to_s.sub(/^process_/, '').to_sym }
      end
    end

    # args class is named after RPC, e.g., #get_things => Get_things_args
    def args_class(service, rpc)
      service.const_get("#{rpc.capitalize}_args")
    end

    # result class is named after RPC, e.g., #do_stuff => Do_stuff_result
    def result_class(service, rpc)
      service.const_get("#{rpc.capitalize}_result")
    end

    ### Thrift deserialisation

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

    # Thrift serialisation

    def serialize(base_struct, transport, protocol)
      base_struct.write(protocol.new(transport))
      transport.tap(&:flush)
    rescue Thrift::ProtocolException, EOFError => e
      raise SerializationError, e
    end

    def serialize_buffer(base_struct, protocol)
      transport = Thrift::MemoryBufferTransport.new
      serialize(base_struct, transport, protocol) # write to output transport, an in-memory buffer
      transport.read(transport.available) # return serialised thrift
    end

    def serialize_stream(base_struct, out_stream, protocol)
      serialize(base_struct, Thrift::IOStreamTransport.new(nil, out_stream), protocol)
    end

    # String and object transforms

    # Used to turn classes to canonical strings for routing and logging, e.g.,
    # - MyServices::Thing::ThingService -> my_services.thing.thing_service
    # - MyServices::Thing::ThingRequest -> my_services.thing.thing_request
    # - MyServices::Thing::BadException -> my_services.thing.bad_exception
    # @param klass [Class]
    def canonical_name(klass)
      klass.name.underscore.tr('/', '.')
    end

    # Recursive object serialiser compatible with anything likely to appear
    # in Thrift, in case ActiveSupport's #as_json monkeypatch is unavailable
    def jsonify(obj)
      return obj.as_json if obj.respond_to?(:as_json) # ActiveSupport shortcut

      case obj
      when nil, false, true, Numeric # directly representable as JSON
        obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[jsonify(k)] = jsonify(v) }
      when Enumerable
        obj.map { |v| jsonify(v) }
      else
        if obj.instance_variables.any?
          obj.instance_variables.each_with_object({}) do |iv, h|
            h[iv.to_s[1..-1].to_sym] = jsonify(obj.instance_variable_get(iv))
          end
        else
          obj.to_s # lowest common denominator serialisation
        end
      end
    end
  end
end
