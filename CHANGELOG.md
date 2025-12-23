## [Ruby Hyperliquid SDK Changelog]

## [0.4.0] - 2025-12-23

- Add Exchange API for write operations (trading)
  - Order placement: `order`, `bulk_orders`, `market_order`
  - Order cancellation: `cancel`, `cancel_by_cloid`, `bulk_cancel`
  - Vault trading support via optional `vault_address` parameter
- Add EIP-712 signing infrastructure for authenticated requests
- Add `eth` gem dependency for cryptographic operations
- SDK now accepts optional `private_key` parameter to enable exchange operations

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
