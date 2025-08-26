# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Hyperliquid errors' do
  describe Hyperliquid::Error do
    it 'can be initialized with just a message' do
      error = described_class.new('Test error')

      expect(error.message).to eq('Test error')
      expect(error.status_code).to be_nil
      expect(error.response_body).to be_nil
    end

    it 'can be initialized with message, status code, and response body' do
      response_body = { 'error' => 'detailed error' }
      error = described_class.new(
        'Test error',
        status_code: 400,
        response_body: response_body
      )

      expect(error.message).to eq('Test error')
      expect(error.status_code).to eq(400)
      expect(error.response_body).to eq(response_body)
    end

    it 'is a StandardError' do
      error = described_class.new('Test')
      expect(error).to be_a(StandardError)
    end
  end

  describe Hyperliquid::ClientError do
    it 'inherits from Hyperliquid::Error' do
      error = described_class.new('Client error')
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::ServerError do
    it 'inherits from Hyperliquid::Error' do
      error = described_class.new('Server error')
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::AuthenticationError do
    it 'inherits from Hyperliquid::ClientError' do
      error = described_class.new('Auth error')
      expect(error).to be_a(Hyperliquid::ClientError)
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::RateLimitError do
    it 'inherits from Hyperliquid::ClientError' do
      error = described_class.new('Rate limit error')
      expect(error).to be_a(Hyperliquid::ClientError)
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::BadRequestError do
    it 'inherits from Hyperliquid::ClientError' do
      error = described_class.new('Bad request error')
      expect(error).to be_a(Hyperliquid::ClientError)
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::NotFoundError do
    it 'inherits from Hyperliquid::ClientError' do
      error = described_class.new('Not found error')
      expect(error).to be_a(Hyperliquid::ClientError)
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::TimeoutError do
    it 'inherits from Hyperliquid::Error' do
      error = described_class.new('Timeout error')
      expect(error).to be_a(Hyperliquid::Error)
    end
  end

  describe Hyperliquid::NetworkError do
    it 'inherits from Hyperliquid::Error' do
      error = described_class.new('Network error')
      expect(error).to be_a(Hyperliquid::Error)
    end
  end
end
