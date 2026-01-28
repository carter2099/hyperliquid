# Error Handling

The SDK provides comprehensive error handling with typed exceptions.

## Usage

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

## Error Classes

| Error Class | Description |
|-------------|-------------|
| `Hyperliquid::Error` | Base error class |
| `Hyperliquid::ClientError` | 4xx errors |
| `Hyperliquid::ServerError` | 5xx errors |
| `Hyperliquid::AuthenticationError` | 401 errors |
| `Hyperliquid::BadRequestError` | 400 errors |
| `Hyperliquid::NotFoundError` | 404 errors |
| `Hyperliquid::RateLimitError` | 429 errors |
| `Hyperliquid::NetworkError` | Connection issues |
| `Hyperliquid::TimeoutError` | Request timeouts |
