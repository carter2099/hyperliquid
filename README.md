# Hyperliquid Ruby SDK

A Ruby SDK for interacting with the Hyperliquid decentralized exchange API.

This is v0.1.0 - an alpha-stage read-only implementation focusing on the Info API endpoints for market data, user information, and order book data.

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

# Create SDK instance (mainnet by default)
sdk = Hyperliquid.new

# Or use testnet
testnet_sdk = Hyperliquid.new(testnet: true)

# Access the Info API
info = sdk.info
```

### Info API Methods

The SDK provides access to all Hyperliquid Info API endpoints:

#### Market Data

```ruby
# Get all market mid prices
mids = sdk.info.all_mids
# => { "BTC" => "50000", "ETH" => "3000", ... }

# Get asset metadata
meta = sdk.info.meta
# => { "universe" => [...] }

# Get extended asset metadata with contexts
meta_ctxs = sdk.info.meta_and_asset_ctxs  
# => { "universe" => [...], "assetCtxs" => [...] }

# Get L2 order book for a coin
book = sdk.info.l2_book("BTC")
# => { "coin" => "BTC", "levels" => [[asks], [bids]], "time" => ... }

# Get candlestick data
candles = sdk.info.candles_snapshot("BTC", "1h", start_time, end_time)
# => [{ "t" => ..., "o" => "50000", "h" => "51000", "l" => "49000", "c" => "50500", "v" => "100" }]
```

#### User Data

```ruby
user_address = "0x..." # Wallet address

# Get user's open orders
orders = sdk.info.open_orders(user_address)
# => [{ "coin" => "BTC", "sz" => "0.1", "px" => "50000", "side" => "A" }]

# Get user's fill history
fills = sdk.info.user_fills(user_address)
# => [{ "coin" => "BTC", "sz" => "0.1", "px" => "50000", "side" => "A", "time" => 1234567890 }]

# Get user's trading state (positions, balances)
state = sdk.info.user_state(user_address)
# => { "assetPositions" => [...], "marginSummary" => {...} }

# Get order status  
status = sdk.info.order_status(user_address, order_id)
# => { "status" => "filled", "sz" => "0.1", "px" => "50000" }
```

### Configuration

```ruby
# Custom timeout (default: 30 seconds)
sdk = Hyperliquid.new(timeout: 60)

# Enable retry logic for handling transient failures (default: disabled)
sdk = Hyperliquid.new(retry_enabled: true)

# Combine multiple configuration options
sdk = Hyperliquid.new(testnet: true, timeout: 60, retry_enabled: true)

# Check which environment you're using
sdk.testnet?  # => false
sdk.base_url  # => "https://api.hyperliquid.xyz"
```

#### Retry Configuration

By default, retry logic is **disabled** for predictable API behavior. When enabled, the SDK will automatically retry requests that fail due to:

- Network connectivity issues (connection failed, timeouts)
- Server errors (5xx status codes)
- Rate limiting (429 status codes)

**Retry Settings:**
- Maximum retries: 2
- Base interval: 0.5 seconds
- Backoff factor: 2x (exponential backoff)
- Randomness: ±50% to prevent thundering herd

**Note:** Retries are disabled by default to avoid unexpected delays in time-sensitive trading applications. Enable only when you want automatic handling of transient failures.

### Error Handling

The SDK provides comprehensive error handling:

```ruby
begin
  orders = sdk.info.open_orders(user_address)
rescue Hyperliquid::AuthenticationError
  # Handle authentication issues
rescue Hyperliquid::RateLimitError  
  # Handle rate limiting
rescue Hyperliquid::ServerError
  # Handle server errors
rescue Hyperliquid::NetworkError
  # Handle network connectivity issues
rescue Hyperliquid::Error => e
  # Handle any other Hyperliquid API errors
  puts "Error: #{e.message}"
  puts "Status: #{e.status_code}" if e.status_code
  puts "Response: #{e.response_body}" if e.response_body
end
```

Available error classes:
- `Hyperliquid::Error` - Base error class
- `Hyperliquid::ClientError` - 4xx errors
- `Hyperliquid::ServerError` - 5xx errors
- `Hyperliquid::AuthenticationError` - 401 errors
- `Hyperliquid::BadRequestError` - 400 errors
- `Hyperliquid::NotFoundError` - 404 errors
- `Hyperliquid::RateLimitError` - 429 errors
- `Hyperliquid::NetworkError` - Connection issues
- `Hyperliquid::TimeoutError` - Request timeouts

## API Reference

### Hyperliquid.new(options = {})

Creates a new SDK instance.

**Parameters:**
- `testnet` (Boolean) - Use testnet instead of mainnet (default: false)  
- `timeout` (Integer) - Request timeout in seconds (default: 30)
- `retry_enabled` (Boolean) - Enable automatic retry logic for transient failures (default: false)

### Info API Methods

All Info methods return parsed JSON responses from the Hyperliquid API.

#### Market Data Methods
- `all_mids()` - Get all market mid prices
- `meta()` - Get asset metadata
- `meta_and_asset_ctxs()` - Get extended asset metadata
- `l2_book(coin)` - Get L2 order book for a coin
- `candles_snapshot(coin, interval, start_time, end_time)` - Get candlestick data

#### User Data Methods  
- `open_orders(user)` - Get user's open orders
- `user_fills(user)` - Get user's fill history
- `user_state(user)` - Get user's trading state
- `order_status(user, oid)` - Get order status

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Run the example:
```bash
ruby example.rb
```

Run tests:
```bash  
rake spec
```

Run tests and linting together:
```bash
rake
```

Run linting:
```bash
rake rubocop
```

## Roadmap

This is v0.1.0 with read-only Info API support. Future versions will include:

- v0.2.0: Trading API (place orders, cancel orders, etc.)
- v0.3.0: WebSocket support for real-time data
- v0.4.0: Advanced trading features

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/carter2099/hyperliquid.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
