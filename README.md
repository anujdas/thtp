# THTP: Thrift-RPC for HTTP

THTP provides a full client/server implementation of Thrift-RPC over an HTTP
transport. Inspired by [twirp](https://github.com/twitchtv/twirp), a similar
project for protobuf-based RPC definitions, THTP cuts down on the complexity of
building a Thrift-RPC service in Ruby by enabling use of the same HTTP servers
already in widespread use with Rails/Sinatra/other Rack applications (e.g.,
[puma](https://github.com/puma/puma)).

THTP already supports a full feature set allowing it to be dropped in place of
the upstream [Apache Thrift](https://github.com/apache/thrift/) socket-based
implementation. Existing Thrift definitions and handler code require zero
changes and can be used with both THTP and Thrift-RPC simultaneously!

THTP also provides built-ins to make real productionised services with minimal
additional work: [ActiveRecord
support](https://github.com/anujdas/thtp/blob/master/lib/thtp/server/middleware.rb#L37-L46),
[logging](https://github.com/anujdas/thtp/blob/master/lib/thtp/server/instrumentation.rb#L72),
[statsd
instrumentation](https://github.com/anujdas/thtp/blob/master/lib/thtp/server/instrumentation.rb#L11),
[exception
captures](https://github.com/anujdas/thtp/blob/master/lib/thtp/server/instrumentation.rb#L194),
and more. All these are built atop the same pluggable extension system, making
it easy to define other hooks if the built-ins don't suffice.

THTP intelligently supports compact, binary, and JSON encoding via headers,
making interacting with services a breeze.

THTP aims to support HTTP/2 via the new wave of asyncio/non-blocking Rack
servers like [falcon](https://github.com/socketry/falcon/), providing all the
benefits of raw-socket Thrift-RPC (multiplexing, efficiency) with none of the
downsides (hard-to-debug, hard-to-test, difficult to load-balance, fragile
services). Even over HTTP/1.1, the THTP client uses a connection pool with
persistent connections to make production use easy and performant.

## Protocol

The THTP protocol implements the full feature set of the Thrift-RPC service
definition language. Given a Thrift service definition like

```thrift
namespace rb THTP.Test

struct AddIntegersRequest {
  1: i32 operand1,
  2: i32 operand2,
}

exception ArgumentException {
  1: string message,
  2: i32 code,
}

service AdditionService {
  i32 add_integers(
    1: AddIntegersRequest request,
  ) throws (
    1: ArgumentException argument_exception,
  ),

  void ping(),
}
```

THTP will respond to requests routed by the service name and RPC. For instance,
calling `add_integers` will `POST /THTP.Test.AdditionService/add_integers` with
the request body containing the Thrift-encoded `AddIntegersRequest` and the
response body containing the Thrift-encoded `i32` sum. Technically, these
values are actually wrapped by the Thrift compiler-generated `*_args` and
`*_result` structs, adding in generic `ApplicationException` support for
unhandled errors. The response code is 200 for any valid response or handled
error, 500 otherwise -- this allows high-level response code metrics to
distinguish and track "known" versus "unknown" behaviour.

Thrift encoding is selected by the request `Content-Type` HTTP header. If
unspecified, JSON encoding will be used by default (this simplifies reading
requests/responses manually). If set to one of the valid Thrift MIME types,
though, the encoding will be inferred and used for both request and response
encoding. These types are:

- `application/vnd.apache.thrift.binary`
- `application/vnd.apache.thrift.compact`
- `application/vnd.apache.thrift.json`

A request to an unknown RPC will return a `404`. Because of the service
namespacing, multiple services may be mounted on a single Rack server, though
this usage is not well-tested.

## Usage

### Server

A minimal handler for the service defined above might look like

```ruby
class AdditionHandler
  def add_integers(request)
    unless request.operand1 && request.operand2
      raise ArgumentException, message: 'Both operands must be provided.'
    end
    request.operand1 + request.operand2
  end

  def ping; end
end
```

This matches the typical Thrift-RPC handler spec and will work as-is for that
server, but using it with THTP is equally simple:

```ruby
STATSD = Datadog::Statsd.new
LOGGER = Logger.new

class AdditionServer < THTP::Server
  def initialize
    super service: THTP::Test::AdditionService, handlers: [AdditionHandler]

    use THTP::Server::Middleware::SchemaValidation
    subscribe THTP::Server::Instrumentation::Metrics.new(STATSD)
    subscribe THTP::Server::Instrumentation::Logging.new(LOGGER)
    subscribe THTP::Server::Instrumentation::Sentry.new(Raven)
  end
end
```

Running the service is as simple as selecting a Rack server (`puma` highly
recommended due to its threading model), writing a `config.ru` like the
following, and running `rackup`:

```
run AdditionServer.new
```

This is just a simple example, with much more possible: check out the provided
instrumentation and middleware to learn more. However, this is all it takes to
produce a high-performance, high-throughput, multi-threaded, instrumented, and
logged service running.

### Client

Assuming default settings on the server, a THTP client can be created as follows:

```ruby
STATSD = Datadog::Statsd.new

class AdditionClient < THTP::Client
  def initialize(**opts)
    super THTP::Test::AdditionService, **opts

    use THTP::Client::Middleware::SchemaValidation
    use THTP::Client::Instrumentation::Metrics,
        from: :calculator_service,
        to: :addition_service,
        statsd: STATSD
  end
end

AdditionClient.new(port: 3000).add_integers(1, 2)
# => 3
```

The same middleware capabilities present in the server exist here as well. The
example above will publish stats to Datadog with latencies, success metrics,
and tagging for responses. As with the server, explore the built-in middlewares
to learn more and see how to extend them or create your own. The client is
highly configurable as well and provides SSL, connection pooling, and timeouts:
see available options in [the
code](https://github.com/anujdas/thtp/blob/5af07dc36373d95ce334ca7e854fcdb320801c53/lib/thtp/client.rb#L96).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'thtp'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install thtp

## Javascript client

An ES6 Javascript client implementation offering most of the Ruby client's
features is also available at [thtp-js](https://github.com/anujdas/thtp-js).
This client is especially useful for SOAs in which a GraphQL orchestration
layer fronts an array of Thrift-RPC services.

Note that it requires some patches to the generated Thrift code to access
internal classes; simple code is provided that should be easy to integrate into
the Thrift compilation phase.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/anujdas/thtp.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
