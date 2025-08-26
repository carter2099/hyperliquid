# frozen_string_literal: true

RSpec.describe Hyperliquid do
  it 'has a version number' do
    expect(Hyperliquid::VERSION).not_to be nil
  end

  describe '.new' do
    it 'creates a new SDK instance with mainnet by default' do
      sdk = Hyperliquid.new
      expect(sdk).to be_a(Hyperliquid::SDK)
      expect(sdk.testnet?).to be false
      expect(sdk.base_url).to eq(Hyperliquid::Constants::MAINNET_API_URL)
    end

    it 'creates a new SDK instance with testnet when specified' do
      sdk = Hyperliquid.new(testnet: true)
      expect(sdk).to be_a(Hyperliquid::SDK)
      expect(sdk.testnet?).to be true
      expect(sdk.base_url).to eq(Hyperliquid::Constants::TESTNET_API_URL)
    end

    it 'uses default timeout when none specified' do
      sdk = Hyperliquid.new
      client = sdk.info.instance_variable_get(:@client)
      connection = client.instance_variable_get(:@connection)
      expect(connection.options.timeout).to eq(Hyperliquid::Constants::DEFAULT_TIMEOUT)
    end

    it 'creates a new SDK instance with custom timeout' do
      sdk = Hyperliquid.new(timeout: 60)
      expect(sdk).to be_a(Hyperliquid::SDK)
      
      client = sdk.info.instance_variable_get(:@client)
      connection = client.instance_variable_get(:@connection)
      expect(connection.options.timeout).to eq(60)
    end
  end

  describe Hyperliquid::SDK do
    let(:sdk) { Hyperliquid.new(testnet: true) }

    it 'has an info client' do
      expect(sdk.info).to be_a(Hyperliquid::Info)
    end

    it "knows if it's using testnet" do
      expect(sdk.testnet?).to be true
    end

    it 'provides the correct base URL' do
      expect(sdk.base_url).to eq(Hyperliquid::Constants::TESTNET_API_URL)
    end
  end
end
