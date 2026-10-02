# Configuration

## Basic Options

```ruby
# Custom timeout in seconds (default: 30), applied separately to connecting,
# sending the request and waiting for the response
sdk = Hyperliquid.new(timeout: 60)

# Retry transient failures of read requests (default: disabled; /exchange is never retried)
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

## Timeout

`timeout:` (seconds, default 30) is used for every phase of a request: opening the connection, writing the request and reading the response. Each phase can take up to that long, so a slow response raises `Hyperliquid::TimeoutError` once no data has arrived for `timeout` seconds.

## Retry Configuration

Retries are **disabled** by default. With `retry_enabled: true`, only read requests are retried:

- `POST /info`: every `sdk.info` method except `tx_details` and `user_details`
- `POST /explorer` on the RPC host: `sdk.info.tx_details` and `sdk.info.user_details`

**`POST /exchange` is never retried**, whatever the failure. Resending a signed action could execute it twice (for example, place the same order twice), so a failed exchange request always raises after exactly one attempt. Check the result (for example with `open_orders` or `order_status`) before you send the action again.

A read request is retried when:

- the response status is 429, 502, 503 or 504
- the connection fails (`Faraday::ConnectionFailed`) or times out (`Faraday::TimeoutError`)

Other statuses (400, 401, 404, 500, …) are not retried and raise their error class immediately.

**Retry Settings:**
- Maximum retries: 2 (at most 3 attempts per read request)
- Wait before retry *n*: 0.5 s × 2^(n−1), plus a random 0–0.25 s (0.5–0.75 s, then 1.0–1.25 s)
- A `Retry-After` or `RateLimit-Reset` response header that asks for a longer wait is honoured

When the last attempt still fails, the SDK raises the same error a single failure would raise (`RateLimitError` for 429, `ServerError` for 5xx, `NetworkError` or `TimeoutError` for network failures).

**Note:** Retries are disabled by default to avoid unexpected delays in time-sensitive trading applications. Enable them only if you want transient read failures handled automatically.
