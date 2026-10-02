# frozen_string_literal: true

# Guards what `gem build` packages: all runtime code, nothing dev-only, and every file the
# runtime code loads. A miss here ships a gem that fails on `require 'hyperliquid'` (or leaks
# scripts/notes) while every other spec still passes against lib/ on disk.
RSpec.describe 'hyperliquid.gemspec packaging' do
  root = File.expand_path('..', __dir__)
  files = Gem::Specification.load(File.join(root, 'hyperliquid.gemspec')).files

  it 'packages every tracked lib/**/*.rb file' do
    tracked = IO.popen(%w[git ls-files -z lib], chdir: root, &:read).split("\0").grep(/\.rb\z/)
    expect(tracked).to include('lib/hyperliquid.rb')
    expect(tracked - files).to be_empty
  end

  it 'packages no dev-only files' do
    dev_prefixes = %w[scripts/ spec/ tools/ local/ .github/ bin/ Gemfile]
    dev_files = %w[CLAUDE.md Rakefile example.rb .rubocop.yml .rspec]
    expect(files.select { |f| f.start_with?(*dev_prefixes) || dev_files.include?(f) }).to be_empty
  end

  it 'packages the target of every require_relative in lib/ (an untracked target would be left out)' do
    missing = Dir[File.join(root, 'lib/**/*.rb')].flat_map do |path|
      File.read(path).scan(/^\s*require_relative\s+['"]([^'"]+)['"]/).flatten.filter_map do |target|
        resolved = File.expand_path("#{target}.rb", File.dirname(path)).delete_prefix("#{root}/")
        "#{path.delete_prefix("#{root}/")} -> #{resolved}" unless files.include?(resolved)
      end
    end
    expect(missing).to be_empty
  end
end
