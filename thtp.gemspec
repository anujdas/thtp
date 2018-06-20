lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'thtp/version'

Gem::Specification.new do |spec|
  spec.name          = 'thtp'
  spec.version       = THTP::VERSION
  spec.authors       = ['Anuj Das']
  spec.email         = ['anujdas@gmail.com']

  spec.summary       = %q{Thrift-RPC for HTTP}
  spec.description   = %q{A client/server implementation of THTP: Thrift-RPC over HTTP as a Rack app}
  spec.homepage      = 'https://github.com/anujdas/thtp'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^spec/}) }
  spec.test_files    = `git ls-files -z`.split("\x0").select { |f| f.match(%r{^spec/}) }
  spec.require_paths = ['lib']

  spec.add_dependency 'connection_pool', '~> 2.0'
  spec.add_dependency 'patron', '~> 0.13'
  spec.add_dependency 'rack', '~> 2.0'
  spec.add_dependency 'thrift', '~> 0.9'

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rubocop', '~> 0.54.0'

  spec.add_development_dependency 'rack-test', '~> 1.0'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'webmock', '~> 3.4'

  # optional dependencies
  spec.add_development_dependency 'anujdas-thrift-validator', '~> 0.2'
end
