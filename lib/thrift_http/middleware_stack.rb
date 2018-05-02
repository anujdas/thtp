require 'thrift_http/utils'

module ThriftHttp
  # An implementation of the middleware pattern (a la Rack) for RPC handling.
  # Extracts RPCs from a Thrift service and passes requests to a handler via
  # a middleware stack. Note, NOT threadsafe -- mount all desired middlewares
  # before calling.
  class MiddlewareStack
    # @param thrift_service [Class] The Thrift service from which to extract RPCs
    # @param handlers [Object,Array<Object>] An object or objects responding to
    #   each defined RPC; if multiple respond, the first will be used
    def initialize(thrift_service, handlers)
      # initialise middleware stack as empty with a generic dispatcher at the bottom
      @stack = []
      @dispatcher = ->(rpc, *rpc_args, **_rpc_opts) do
        handler = Array(handlers).find { |h| h.respond_to?(rpc) }
        raise NoMethodError, "No handler for rpc #{rpc}" unless handler
        handler.public_send(rpc, *rpc_args) # opts are for middleware use only
      end
      # define instance methods for each RPC
      Utils.extract_rpcs(thrift_service).each do |rpc|
        define_singleton_method(rpc) { |*rpc_args_and_opts| call(rpc, *rpc_args_and_opts) }
      end
    end

    # Nests a middleware at the bottom of the stack (closest to the function
    # call). A middleware is any class implementing #call and calling app.call
    # in turn., i.e.,
    #   class PassthroughMiddleware
    #     def initialize(app, *opts)
    #       @app = app
    #     end
    #     def call(rpc, *rpc_args, **rpc_opts)
    #       @app.call(rpc, *rpc_args, **rpc_opts)
    #     end
    #   end
    def use(middleware_class, *middleware_args)
      @stack << [middleware_class, middleware_args]
    end

    # Freezes and execute the middleware stack culminating in the RPC itself
    def call(rpc, *rpc_args, **rpc_opts)
      compose.call(rpc, *rpc_args, **rpc_opts)
    end

    private

    # compose stack functions into one callable: [f, g, h] => f . g . h
    def compose
      @app ||= @stack.freeze.reverse_each. # rubocop:disable Naming/MemoizedInstanceVariableName
        reduce(@dispatcher) { |app, (mw, mw_args)| mw.new(app, *mw_args) }
    end
  end
end
