# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Ruby SDK for the Hyperliquid decentralized exchange API. The current version (0.3.0) is **read-only** and supports only the Info endpoints. Future versions will include trading capabilities and WebSocket support.

**Target Ruby Version**: 3.4.0+

## Development Commands

### Running Tests
```bash
# Run all tests
rake spec

# Run tests and linting together (default rake task)
rake
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

### Setup
```bash
# Install dependencies
bin/setup
```

## Architecture

### Core Components

**Hyperliquid::SDK** (`lib/hyperliquid.rb`)
- Main entry point created via `Hyperliquid.new(testnet:, timeout:, retry_enabled:)`
- Manages environment selection (mainnet vs testnet)
- Exposes the `info` API client

**Hyperliquid::Client** (`lib/hyperliquid/client.rb`)
- Low-level HTTP client built on Faraday
- Handles all POST requests to the Hyperliquid API
- Manages retry logic (disabled by default, opt-in via `retry_enabled: true`)
- Converts HTTP errors into typed exceptions

**Hyperliquid::Info** (`lib/hyperliquid/info.rb`)
- High-level API client for all Info endpoints
- Organized into three sections:
  1. **General Info**: Market data, user orders, fills, rate limits, portfolios, referrals, fees, staking
  2. **Perpetuals**: Perp DEXs, metadata, user state, funding rates, open interest
  3. **Spot**: Spot tokens, balances, deploy auctions, token details
- All methods accept user wallet addresses and return parsed JSON responses

**Hyperliquid::Constants** (`lib/hyperliquid/constants.rb`)
- API URLs for mainnet and testnet
- Endpoint paths
- Default timeout values

**Hyperliquid::Errors** (`lib/hyperliquid/errors.rb`)
- Typed exception hierarchy for API errors
- Base class: `Hyperliquid::Error`
- Specific errors: `ClientError`, `ServerError`, `AuthenticationError`, `RateLimitError`, `BadRequestError`, `NotFoundError`, `TimeoutError`, `NetworkError`

### API Request Pattern

All API requests follow this pattern:
1. SDK method called (e.g., `sdk.info.all_mids`)
2. Info class builds request body with `type` field (e.g., `{ type: 'allMids' }`)
3. Client POSTs JSON body to `/info` endpoint
4. Client parses response and handles errors
5. Parsed JSON returned to caller

### Testing

- Uses RSpec for testing
- WebMock for HTTP mocking
- Spec helper configures WebMock to reset between tests
- Test files mirror source structure: `spec/hyperliquid/{client,info,errors}_spec.rb`

### Code Style

RuboCop configuration (`.rubocop.yml`):
- Targets Ruby 3.4.3
- Allows longer methods (max 50 lines) for complex logic
- Disables class length checks (Info class implements ~40+ API endpoints)
- Excludes block length checks for specs
- Enables NewCops by default

## Key Implementation Details

### Retry Logic
- **Disabled by default** for predictable behavior in time-sensitive trading
- When enabled: max 2 retries, 0.5s base interval, exponential backoff (2x), ±50% randomness
- Retries on: connection failures, timeouts, 429 (rate limit), 5xx errors

### API Endpoints
- All requests POST to `/info` endpoint
- Request body always includes `type` field indicating the operation
- Optional parameters (like `dex` for perp DEXs or `end_time` for time ranges) only included if provided

### Time Parameters
- All timestamps are in **milliseconds** (not seconds)
- Methods with time ranges support optional `end_time` parameter

### Spot Markets
- Use `"{BASE}/USDC"` format when available (e.g., `"PURR/USDC"`)
- Otherwise use index alias `"@{index}"` from `spot_meta["universe"]`

### Optional Parameters
- Many methods accept optional parameters (e.g., `dex: nil`, `end_time = nil`)
- These are conditionally added to request body only when provided
- Common pattern: `body[:field] = value if value`

## Development Workflow

1. Make changes to library code in `lib/hyperliquid/`
2. Add/update tests in `spec/`
3. Run tests: `rake spec`
4. Run linter: `rake rubocop`
5. Test in console: `bin/console`
6. Run example script: `ruby example.rb`

## Future Additions

When trading API support is added, expect:
- New `Hyperliquid::Exchange` class for order placement/cancellation
- Authentication via wallet signing
- WebSocket client for real-time data streams
- State management for open orders and positions
