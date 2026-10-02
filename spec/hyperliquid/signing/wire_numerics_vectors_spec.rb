# frozen_string_literal: true

require 'spec_helper'

# Python-captured numeric wire tables (fixture written by tools/parity/capture_numerics.py via
# tools/parity/regenerate.sh). The strings produced here are what the order/trigger price and size fields carry,
# so they are part of the signed msgpack bytes.
RSpec.describe Hyperliquid::Exchange, 'wire numerics (Python SDK parity)' do
  fixture = JSON.parse(File.read(File.expand_path('../../fixtures/parity/numerics.json', __dir__)))

  let(:client) { Hyperliquid::Client.new(base_url: Hyperliquid::Constants::TESTNET_API_URL) }
  let(:exchange) do
    described_class.new(
      client: client,
      signer: Hyperliquid::Signing::Signer.new(private_key: "0x#{'11' * 32}", testnet: true),
      info: Hyperliquid::Info.new(client),
      testnet: true
    )
  end

  describe '#calculate_slippage_price matches Python Exchange._slippage_price' do
    fixture['slippage'].each do |row|
      side = row['is_buy'] ? 'buy' : 'sell'
      it "#{row['coin']} (szDecimals #{row['sz_decimals']}) mid #{row['mid']} #{side} " \
         "slippage #{row['slippage']} -> #{row['wire']}" do
        metadata = { sz_decimals: row['sz_decimals'], is_spot: row['is_spot'] }
        allow(exchange).to receive(:asset_metadata).with(row['coin']).and_return(metadata)

        price = exchange.send(:calculate_slippage_price, row['coin'], row['mid'], row['is_buy'], row['slippage'])

        expect(BigDecimal(price)).to eq(BigDecimal(row['px'].to_s))
        expect(exchange.send(:float_to_wire, price)).to eq(row['wire'])
      end
    end
  end

  describe '#float_to_wire matches Python float_to_wire' do
    fixture['float_to_wire'].each do |row|
      if row['wire'].nil?
        it "rejects #{row['x'].inspect} (more than 8 decimals of precision)" do
          expect { exchange.send(:float_to_wire, row['x']) }
            .to raise_error(ArgumentError, /float_to_wire causes rounding/)
        end
      else
        # Deliberate divergence: Python returns "-0" for -0.0 / tiny negatives because its `rounded == "-0"` guard
        # never matches the "%.8f" output ("-0.00000000"); Ruby applies the guard's intent and sends "0".
        expected = row['wire'] == '-0' ? '0' : row['wire']

        it "formats #{row['x'].inspect} as #{expected.inspect}" do
          expect(exchange.send(:float_to_wire, row['x'])).to eq(expected)
        end
      end
    end
  end
end
