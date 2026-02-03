# frozen_string_literal: true

require_relative 'lib/hyperliquid/version'

Gem::Specification.new do |spec|
  spec.name = 'hyperliquid'
  spec.version = Hyperliquid::VERSION
  spec.authors = ['carter2099']
  spec.email = ['carter2077@pm.me']

  spec.summary = 'Ruby SDK for Hyperliquid API'
  spec.description = "A Ruby SDK for interacting with Hyperliquid's decentralized exchange API"
  spec.homepage = 'https://github.com/carter2099/hyperliquid'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.4.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/carter2099/hyperliquid'
  spec.metadata['changelog_uri'] = 'https://github.com/carter2099/hyperliquid/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Add gem dependencies
  spec.add_dependency 'eth', '~> 0.5'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-retry', '~> 2.0'
  spec.add_dependency 'msgpack', '~> 1.7'
  spec.add_dependency 'ws_lite', '~> 1.0.0'
end
