#!/usr/bin/env ruby
# frozen_string_literal: true

# Hyperliquid Ruby SDK - Testnet Integration Tests
#
# This is a convenience wrapper that runs all integration tests.
# Individual tests live in scripts/ and can be run standalone.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby test_integration.rb
#
# Run a single test:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb
#
# See scripts/test_all.rb for the full list.

load File.join(__dir__, 'scripts', 'test_all.rb')
