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
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/carter2099/hyperliquid'
  spec.metadata['changelog_uri'] = 'https://github.com/carter2099/hyperliquid/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Ship runtime code and user-facing docs only (allowlist over tracked files).
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?('lib/', 'docs/') || %w[README.md CHANGELOG.md LICENSE.txt SECURITY.md].include?(f)
    end
  end
  spec.require_paths = ['lib']

  # Add gem dependencies
  spec.add_dependency 'eth', '~> 0.5'
  spec.add_dependency 'faraday', '~> 2.0'
  spec.add_dependency 'faraday-retry', '~> 2.0'
  spec.add_dependency 'msgpack', '~> 1.7'
  spec.add_dependency 'ws_lite', '~> 1.0.1'
end
