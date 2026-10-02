#!/usr/bin/env ruby
# frozen_string_literal: true

# Hyperliquid Ruby SDK - Automated Integration Test Runner
#
# Every script in scripts/ is automated-safe in its default mode; destructive
# or locking variants are opt-in CLI args on individual scripts. This file is
# kept because the scheduled hyperliquid-run invokes it; the list lives in test_all.rb.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_automated.rb

load File.join(__dir__, 'test_all.rb')
