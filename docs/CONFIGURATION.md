# Configuration

## Basic Options

```ruby
# Custom timeout (default: 30 seconds)
sdk = Hyperliquid.new(timeout: 60)

# Enable retry logic for handling transient failures (default: disabled)
sdk = Hyperliquid.new(retry_enabled: true)

# Enable trading with a private key
sdk = Hyperliquid.new(private_key: ENV['HYPERLIQUID_PRIVATE_KEY'])

# Set global order expiration (orders expire after this timestamp)
expires_at_ms = (Time.now.to_f * 1000).to_i + 30_000  # 30 seconds from now
sdk = Hyperliquid.new(
  private_key: ENV['HYPERLIQUID_PRIVATE_KEY'],
  expires_after: expires_at_ms
)

# Combine multiple configuration options
sdk = Hyperliquid.new(
  testnet: true,
  timeout: 60,
  retry_enabled: true,
  private_key: ENV['HYPERLIQUID_PRIVATE_KEY'],
  expires_after: expires_at_ms
)

# Check which environment you're using
sdk.testnet?  # => false
sdk.base_url  # => "https://api.hyperliquid.xyz"

# Check if exchange is available (private_key was provided)
sdk.exchange  # => nil if no private_key, Hyperliquid::Exchange instance otherwise
```

## Retry Configuration

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
