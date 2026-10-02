# frozen_string_literal: true

require 'webmock/rspec'

# Must start before the SDK is loaded so method coverage sees every lib/ definition.
require_relative 'support/method_coverage'

require 'hyperliquid'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

WebMock.disable_net_connect!

RSpec.configure do |config|
  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.raise_errors_for_deprecations!
  config.filter_run_when_matching :focus

  # Random order surfaces order dependence; rerun a failure with `--seed N` from the printed seed.
  config.order = :random
  Kernel.srand config.seed
end
