# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Ruby SDK for the Hyperliquid decentralized exchange API. The current version (0.4.0) supports both **read operations** (Info API) and **authenticated write operations** (Exchange API) for trading.

**Target Ruby Version**: 3.4.0+

## Development Commands

### Running Tests
```bash
# Run all tests
rake spec

# Run tests and linting together (default rake task)
rake

# Run a single test file
bundle exec rspec spec/hyperliquid/cloid_spec.rb

# Run a specific test by line number
bundle exec rspec spec/hyperliquid/cloid_spec.rb:62
```

### Linting
```bash
# Run RuboCop linter
rake rubocop
```

### Interactive Console
```bash
# Open an interactive console with the SDK loaded
bin/console
```

### Example Script
```bash
# Run the example usage script
ruby example.rb
```

### Integration Testing (Testnet)
```bash
# Run the testnet integration test (requires private key)
# Get testnet funds from: https://app.hyperliquid-testnet.xyz
HYPERLIQUID_PRIVATE_KEY=0x... ruby test_integration.rb
```

The integration test executes real trades on testnet:
1. Spot market roundtrip (buy/sell PURR/USDC)
2. Spot limit order (place and cancel)
3. Perp market roundtrip (long/close BTC)
4. Perp limit order (place short, cancel)

### Setup
```bash
# Install dependencies
bin/setup
```

## Architecture

### Core Components

**Hyperliquid::SDK** (`lib/hyperliquid.rb`)
- Main entry point created via `Hyperliquid.new(testnet:, timeout:, retry_enabled:, private_key:, expires_after:)`
- Manages environment selection (mainnet vs testnet)
- Exposes the `info` API client (always available)
- Exposes the `exchange` API client (when `private_key` provided)

**Hyperliquid::Client** (`lib/hyperliquid/client.rb`)
- Low-level HTTP client built on Faraday
- Handles all POST requests to the Hyperliquid API
- Manages retry logic (disabled by default, opt-in via `retry_enabled: true`)
- Converts HTTP errors into typed exceptions

**Hyperliquid::Info** (`lib/hyperliquid/info.rb`)
- High-level API client for all Info endpoints (read-only)
- Organized into three sections:
  1. **General Info**: Market data, user orders, fills, rate limits, portfolios, referrals, fees, staking
  2. **Perpetuals**: Perp DEXs, metadata, user state, funding rates, open interest
  3. **Spot**: Spot tokens, balances, deploy auctions, token details
- All methods accept user wallet addresses and return parsed JSON responses

**Hyperliquid::Exchange** (`lib/hyperliquid/exchange.rb`)
- High-level API client for Exchange endpoints (authenticated write operations)
- Order placement: `order`, `bulk_orders`, `market_order`
- Order cancellation: `cancel`, `cancel_by_cloid`, `bulk_cancel`, `bulk_cancel_by_cloid`
- Supports trigger orders (stop loss / take profit)
- Supports vault trading via `vault_address` parameter
- Caches asset metadata for efficient lookups

**Hyperliquid::Signing::Signer** (`lib/hyperliquid/signing/signer.rb`)
- EIP-712 signature generation using phantom agent scheme
- Matches official Python SDK signing algorithm exactly
- Supports vault address and expiration in signature

**Hyperliquid::Signing::EIP712** (`lib/hyperliquid/signing/eip712.rb`)
- EIP-712 domain and type definitions
- L1 chain ID (1337) and source identifiers ('a' mainnet, 'b' testnet)

**Hyperliquid::Cloid** (`lib/hyperliquid/cloid.rb`)
- Type-safe client order ID class
- Validates 16-byte hex format (0x + 32 hex characters)
- Factory methods: `from_int`, `from_str`, `from_uuid`, `random`

**Hyperliquid::Constants** (`lib/hyperliquid/constants.rb`)
- API URLs for mainnet and testnet
- Endpoint paths (`/info`, `/exchange`)
- Default timeout values

**Hyperliquid::Errors** (`lib/hyperliquid/errors.rb`)
- Typed exception hierarchy for API errors
- Base class: `Hyperliquid::Error`
- Specific errors: `ClientError`, `ServerError`, `AuthenticationError`, `RateLimitError`, `BadRequestError`, `NotFoundError`, `TimeoutError`, `NetworkError`

### API Request Pattern

**Info API (read-only):**
1. SDK method called (e.g., `sdk.info.all_mids`)
2. Info class builds request body with `type` field (e.g., `{ type: 'allMids' }`)
3. Client POSTs JSON body to `/info` endpoint
4. Client parses response and handles errors
5. Parsed JSON returned to caller

**Exchange API (authenticated):**
1. SDK method called (e.g., `sdk.exchange.order(...)`)
2. Exchange class builds action payload with order/cancel details
3. Signer generates EIP-712 signature over msgpack-encoded action
4. Exchange POSTs signed payload to `/exchange` endpoint
5. Client parses response and handles errors
6. Parsed JSON returned to caller

### Testing

- Uses RSpec for testing
- WebMock for HTTP mocking
- Spec helper configures WebMock to reset between tests
- Test files mirror source structure in `spec/`

### Code Style

RuboCop configuration (`.rubocop.yml`):
- Targets Ruby 3.4.0+
- Allows longer methods (max 50 lines) for complex logic
- Disables class length checks (Info/Exchange classes implement many endpoints)
- Excludes block length checks for specs
- Enables NewCops by default

## Key Implementation Details

### Retry Logic
- **Disabled by default** for predictable behavior in time-sensitive trading
- When enabled: max 2 retries, 0.5s base interval, exponential backoff (2x), ±50% randomness
- Retries on: connection failures, timeouts, 429 (rate limit), 5xx errors

### API Endpoints
- Info requests POST to `/info` endpoint
- Exchange requests POST to `/exchange` endpoint
- Request body includes `type` field indicating the operation

### Time Parameters
- All timestamps are in **milliseconds** (not seconds)
- Methods with time ranges support optional `end_time` parameter
- `expires_after` is an absolute timestamp in milliseconds

### Signature Generation (Python SDK Parity)
The signing implementation matches the official Python SDK exactly:
- **Action hash**: `keccak256(msgpack(action) + nonce(8B BE) + vault_flag + [vault_addr] + [expires_flag + expires_after])`
- **Phantom agent**: `{ source: 'a'|'b', connectionId: action_hash }`
- **EIP-712 signature** over phantom agent with Exchange domain

### Float to Wire Format
Numeric values are converted to strings matching Python SDK `float_to_wire`:
- 8 decimal precision
- Rounding tolerance validation (1e-12)
- Trailing zero normalization (no scientific notation)

### Market Order Price Calculation
Market orders use Python SDK `_slippage_price` algorithm:
- Apply slippage to mid price
- Round to 5 significant figures
- Round to asset-specific decimal places: `(6 for perp, 8 for spot) - szDecimals`

### Client Order IDs (Cloid)
- Must be 16 bytes in hex format: `0x` + 32 hex characters
- Use `Hyperliquid::Cloid` class for type safety and validation
- Factory methods: `from_int(n)`, `from_str(s)`, `from_uuid(uuid)`, `random`

## Development Workflow

1. Make changes to library code in `lib/hyperliquid/`
2. Add/update tests in `spec/`
3. Run tests: `rake spec`
4. Run linter: `rake rubocop`
5. Test in console: `bin/console`
6. Run example script: `ruby example.rb`

