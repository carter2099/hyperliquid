# Development

## Setup

After checking out the repo, run `bin/setup` to install dependencies.

```bash
bin/setup
```

## Running Tests

```bash
# Run all tests
rake spec

# Run tests and linting together (default)
rake
```

## Linting

```bash
rake rubocop
```

## Interactive Console

```bash
bin/console
```

This opens an interactive prompt with the SDK loaded for experimentation.

## Example Script

```bash
ruby example.rb
```

## Integration Testing (Testnet)

For real trading tests on testnet:

```bash
# Get testnet funds from: https://app.hyperliquid-testnet.xyz
HYPERLIQUID_PRIVATE_KEY=0x... ruby test_integration.rb
```

The integration test executes real trades on testnet:
1. Spot market roundtrip (buy/sell PURR/USDC)
2. Spot limit order (place and cancel)
3. Perp market roundtrip (long/close BTC)
4. Perp limit order (place short, cancel)
