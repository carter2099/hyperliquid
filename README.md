# Hyperliquid Ruby SDK

[![Gem Version](https://badge.fury.io/rb/hyperliquid.svg)](https://rubygems.org/gems/hyperliquid)
[![Downloads](https://img.shields.io/gem/dt/hyperliquid.svg)](https://rubygems.org/gems/hyperliquid)
[![CI](https://github.com/carter2099/hyperliquid/actions/workflows/main.yml/badge.svg)](https://github.com/carter2099/hyperliquid/actions)

A Ruby SDK for interacting with the Hyperliquid decentralized exchange API.

Full-featured SDK with Info API (market data), Exchange API (trading), real-time WebSocket streaming, and HIP-3 builder-deployed perpetuals support.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hyperliquid'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install hyperliquid

### rubyzip 3 (optional)

This gem signs with [`eth`](https://github.com/q9f/eth.rb), which depends on
`rbsecp256k1 ~> 6.0`. The latest `rbsecp256k1` on RubyGems (6.0.0) pins `rubyzip ~> 2.3`,
so your app stays on rubyzip 2.x and scanners report
[GHSA-47m2-wp7j-p9vc](https://github.com/advisories/GHSA-47m2-wp7j-p9vc) (fixed in rubyzip
3.4.0).

The practical risk is small. `rbsecp256k1` uses rubyzip only while installing, to unpack
its libsecp256k1 source archive, which is checked against a pinned SHA-256. Neither this
SDK nor `eth` loads rubyzip at runtime.

Upstream has merged rubyzip 3 support
([etscrivner/rbsecp256k1#85](https://github.com/etscrivner/rbsecp256k1/pull/85)), but it
is not on RubyGems yet. Until that release, you can move to rubyzip 3 by adding the
maintained fork to your own Gemfile. The fork is version 6.1.0: it allows `rubyzip >= 3.4,
< 4` and bundles libsecp256k1 0.8.0, and it still satisfies `eth`'s `~> 6.0` requirement.

```ruby
gem 'hyperliquid'
gem 'rbsecp256k1', github: 'carter2099/rbsecp256k1', ref: 'bbfe3e346828e39d13aa590cca7cc74f663d2fde'
```

Then run `bundle update rbsecp256k1 rubyzip`. This SDK's own test suite and CI run against
that fork.

## Usage

### Basic Setup

```ruby
require 'hyperliquid'

# Create SDK instance for read-only operations (mainnet by default)
sdk = Hyperliquid.new

# Or use testnet
testnet_sdk = Hyperliquid.new(testnet: true)

# Access the Info API (read operations)
info = sdk.info

# For trading operations, provide a private key
trading_sdk = Hyperliquid.new(
  testnet: true,
  private_key: ENV['HYPERLIQUID_PRIVATE_KEY']
)

# Access the Exchange API (write operations)
exchange = trading_sdk.exchange
```

### Documentation

- [API Reference](docs/API.md) - Complete list of available methods
- [Examples](docs/EXAMPLES.md) - Code examples for Info and Exchange APIs
- [Web Sockets](docs/WS.md) - Web Sockets implementation
- [Configuration](docs/CONFIGURATION.md) - SDK configuration options
- [Error Handling](docs/ERRORS.md) - Error types and handling
- [Development](docs/DEVELOPMENT.md) - Contributing and running tests

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/carter2099/hyperliquid.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
