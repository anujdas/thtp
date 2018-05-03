require 'bundler/setup'
require 'thtp'

# test helpers
require 'rack/test'
require 'webmock'

# require all spec helpers
Dir[File.expand_path('support/**/*.rb', __dir__)].each do |f|
  require f
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Prevents mocking or stubbing a method that does not exist
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.warnings = true

  config.profile_examples = 10

  # randomise test order, allowing repeatable runs via --seed
  config.order = :random
  Kernel.srand config.seed
end
