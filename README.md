# Hyperliquid Ruby SDK

[![Gem Version](https://badge.fury.io/rb/hyperliquid.svg)](https://rubygems.org/gems/hyperliquid)
[![Downloads](https://img.shields.io/gem/dt/hyperliquid.svg)](https://rubygems.org/gems/hyperliquid)
[![CI](https://github.com/carter2099/hyperliquid/actions/workflows/main.yml/badge.svg)](https://github.com/carter2099/hyperliquid/actions)

A Ruby SDK for interacting with the Hyperliquid decentralized exchange API.

The SDK supports both read operations (Info API) and authenticated write operations (Exchange API) for trading.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hyperliquid'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install hyperliquid

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
- [Configuration](docs/CONFIGURATION.md) - SDK configuration options
- [Error Handling](docs/ERRORS.md) - Error types and handling
- [Development](docs/DEVELOPMENT.md) - Contributing and running tests

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/carter2099/hyperliquid.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
