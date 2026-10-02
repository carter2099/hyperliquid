# frozen_string_literal: true

require 'open3'
require 'rbconfig'

# Consumers running with `ruby -w` (or RUBYOPT=-W) must not see warnings from this gem's own
# files when they require it and build an SDK. Warnings from third-party gems are ignored.
RSpec.describe 'Loading the gem under ruby -w' do
  root = File.expand_path('..', __dir__)
  lib = File.join(root, 'lib')

  it 'requires hyperliquid and builds an SDK without warnings from lib/' do
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, '-w', '-rbundler/setup', "-I#{lib}",
      '-e', 'require "hyperliquid"; Hyperliquid.new(testnet: true); print :ok',
      chdir: root
    )
    own = stderr.lines.select { |line| line.include?("#{lib}/") || line.start_with?('lib/') }

    expect(own).to be_empty
    expect([status.success?, stdout]).to eq([true, 'ok']), stderr
  end
end
