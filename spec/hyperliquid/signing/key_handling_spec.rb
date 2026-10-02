# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Private key handling' do
  let(:key_hex) { 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' }
  let(:expected_address) { '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' }

  def expect_redacted(object)
    [object.inspect, object.to_s].each do |text|
      expect(text).not_to include(key_hex)
      expect(text.downcase).not_to include(key_hex)
    end
  end

  describe 'redaction' do
    ['', '0x'].each do |prefix|
      context "with a #{prefix.empty? ? 'bare' : '0x-prefixed'} key" do
        let(:private_key) { "#{prefix}#{key_hex}" }

        it 'keeps the key out of Signer#inspect and #to_s while showing the address' do
          signer = Hyperliquid::Signing::Signer.new(private_key: private_key, testnet: true)

          expect_redacted(signer)
          expect(signer.inspect).to include(expected_address)
        end

        it 'keeps the key out of Exchange#inspect and #to_s' do
          sdk = Hyperliquid.new(testnet: true, private_key: private_key)

          expect_redacted(sdk.exchange)
          expect(sdk.exchange.inspect).to include(expected_address)
        end

        it 'keeps the key out of SDK#inspect and #to_s' do
          expect_redacted(Hyperliquid.new(testnet: true, private_key: private_key))
        end
      end
    end
  end

  describe 'validation' do
    invalid_keys = {
      'an empty string' => '',
      'a bare 0x' => '0x',
      '63 hex characters' => 'a' * 63,
      '65 hex characters' => 'a' * 65,
      '0x plus 63 hex characters' => "0x#{'a' * 63}",
      'non-hex characters' => "0x#{'g' * 64}",
      'surrounding whitespace' => " #{'a' * 64}\n",
      'an uppercase 0X prefix' => "0X#{'a' * 64}",
      'nil' => nil,
      'an Integer' => 1
    }

    invalid_keys.each do |description, bad_key|
      it "rejects #{description} with an ArgumentError that does not echo the input" do
        echo = bad_key.is_a?(String) ? bad_key.strip.delete_prefix('0x').delete_prefix('0X') : ''

        expect { Hyperliquid::Signing::Signer.new(private_key: bad_key) }
          .to raise_error(ArgumentError) { |e| expect(e.message).not_to include(echo) unless echo.empty? }
      end
    end

    it 'makes Hyperliquid.new(private_key: "") raise instead of building an exchange' do
      expect { Hyperliquid.new(private_key: '') }.to raise_error(ArgumentError, /private_key/)
    end

    it 'derives the same address from a key with and without the 0x prefix' do
      bare = Hyperliquid::Signing::Signer.new(private_key: key_hex)
      prefixed = Hyperliquid::Signing::Signer.new(private_key: "0x#{key_hex}")

      expect(bare.address).to eq(expected_address)
      expect(prefixed.address).to eq(expected_address)
    end

    it 'accepts uppercase hex digits' do
      expect(Hyperliquid::Signing::Signer.new(private_key: key_hex.upcase).address).to eq(expected_address)
    end
  end
end
