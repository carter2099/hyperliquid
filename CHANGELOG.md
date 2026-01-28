## [Ruby Hyperliquid SDK Changelog]

## [0.4.1] - 2025-01-28

- Reorganize documentation for improved readability
  - Streamline README with basic setup and links to detailed docs
  - Add `docs/API.md` with complete method reference
  - Add `docs/EXAMPLES.md` with Info and Exchange code examples
  - Add `docs/CONFIGURATION.md` with SDK options and retry settings
  - Add `docs/ERRORS.md` with error handling guide
  - Add `docs/DEVELOPMENT.md` with setup and testing instructions

## [0.4.0] - 2025-01-27

- Add Exchange API for authenticated write operations (trading)
  - Order placement: `order`, `bulk_orders`, `market_order`
  - Order cancellation: `cancel`, `cancel_by_cloid`, `bulk_cancel`, `bulk_cancel_by_cloid`
  - Trigger orders (stop loss / take profit) support
  - Vault trading support via optional `vault_address` parameter
  - Order expiration support via `expires_after` parameter
- Add EIP-712 signing infrastructure matching official Python SDK
  - Phantom agent signing scheme
  - Full parity with Python SDK signature generation
- Add new dependencies: `eth` (~> 0.5), `msgpack` (~> 1.7)
- SDK now accepts optional `private_key` and `expires_after` parameters

## [0.3.0] - 2025-09-24

- Full parity with all Hyperliquid Info APIs
  - All Info APIs implemented
  - Code, tests, and docs reflect structure of official Hyperliquid API documentation

## [0.2.0] - 2025-09-24

- Add info endpoints for user spot data

## [0.1.1] - 2025-09-23

- Fixed retry logic, make retry logic disabled by default

## [0.1.0] - 2025-08-21

- Initial release which includes info endpoints for market and user perps data
