# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in hyperliquid.gemspec
gemspec

gem 'irb'
gem 'rake', '~> 13.0'

gem 'rspec', '~> 3.0'
gem 'webmock', '~> 3.0'

gem 'rubocop', '~> 1.21'

# rbsecp256k1 from Carter's fork (6.1.0, rubyzip >= 3.4) until upstream publishes a
# release off rubyzip 2.x (GHSA-47m2-wp7j-p9vc). Dev/CI lockfile only: the gemspec
# cannot use git sources, so published-gem consumers still resolve rubygems 6.0.0.
# Pinned to a full SHA; do not `bundle update` this ref without review.
gem 'rbsecp256k1', github: 'carter2099/rbsecp256k1', ref: 'bbfe3e346828e39d13aa590cca7cc74f663d2fde'
