# frozen_string_literal: true

require 'spec_helper'

# EIP-712 user-signed vectors for every Signing::EIP712::*_TYPES table, signed by eth_account. Fixture written by
# tools/parity/capture_eip712_user_signed_vectors.py (via tools/parity/regenerate.sh); each row's `source` records
# whether the table came from the Python SDK (signed through its own sign_* function) or, where Python 0.24.0 has
# no such action, from the TS SDK @nktkas/hyperliquid 0.33.1.
RSpec.describe Hyperliquid::Signing::EIP712, 'user-signed vectors' do
  fixture = JSON.parse(File.read(File.expand_path('../../fixtures/parity/eip712_user_signed_vectors.json', __dir__)))
  vectors = fixture['vectors']

  it 'has a vector for every *_TYPES table' do
    expect(described_class.constants.grep(/_TYPES\z/).map(&:to_s))
      .to match_array(vectors.map { |v| v['constant'] }.uniq)
  end

  vectors.group_by { |v| v['constant'] }.each do |constant, rows|
    describe constant do
      it "declares #{rows.first['primary_type']} with the upstream field names, types and order" do
        table = described_class.const_get(constant)
        normalized = table.to_h do |primary_type, fields|
          [primary_type.to_s, fields.map { |f| { 'name' => f[:name].to_s, 'type' => f[:type] } }]
        end

        expect(normalized).to eq(rows.first['primary_type'] => rows.first['types'])
      end

      rows.each do |row|
        it "reproduces the #{row['chain']} signature" do
          signer = Hyperliquid::Signing::Signer.new(private_key: fixture['private_key'],
                                                    testnet: row['chain'] == 'Testnet')

          signature = signer.sign_user_signed_action(
            row['message'].transform_keys(&:to_sym), row['primary_type'], described_class.const_get(constant)
          )

          expect(signature).to eq(r: row['r'], s: row['s'], v: row['v'])
        end
      end
    end
  end
end
