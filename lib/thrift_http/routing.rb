require 'mustermann'
require 'rack'

module ThriftHttp
  # Basic routing at a class level for HTTP verbs and paths
  module Routing
    def self.included(base)
      base.extend ClassMethods
    end

    Route = Struct.new(:matcher, :handler) # route-in-waiting
    MatchedRoute = Struct.new(:handler, :path_params) # route-no-longer-waiting

    # Methods extended onto the including class
    module ClassMethods
      protected

      # metamagic to ensure subclasses propagate routes correctly
      def inherited(subclass)
        super
        subclass.inherit_routes(routes)
      end

      def inherit_routes(super_routes)
        @routes = super_routes
      end

      private

      # A hash of HTTP method => Array<Route>
      def routes
        @routes ||= Hash.new([])
      end

      # route builder; accept either a method name or a block to be executed
      # @param request_method [String] an HTTP verb, one of GET/POST/PATCH/DELETE/etc.
      # @param pattern [String, Regexp] anything matchable against a path, e.g., /:a/:b
      # @param method_sym [Symbol?] name of a method to be executed on path match
      # @param block [Proc?] an executable Proc to be eval'd on path match
      def map_route(request_method, pattern, method_sym = nil, &block)
        raise ArgumentError, 'either method or block must be specified' unless !!method_sym ^ block
        routes[request_method] ||= []
        routes[request_method] << Route.new(Mustermann.new(pattern), block || method_sym.to_proc)
      end

      def get(matcher, method_sym = nil, &block)
        map_route(Rack::GET, matcher, method_sym, &block)
      end

      def post(matcher, method_sym = nil, &block)
        map_route(Rack::POST, matcher, method_sym, &block)
      end

      # actual matcher; accepts a request and returns a route if one exists
      # @param request [Rack::Request]
      # @return [MatchedRoute?]
      def match_route(request)
        routes[request.request_method].find do |route|
          matches = route.matcher.params(request.path_info)
          return MatchedRoute.new(route.handler, matches.symbolize_keys) if matches
        end
      end
    end
  end
end
