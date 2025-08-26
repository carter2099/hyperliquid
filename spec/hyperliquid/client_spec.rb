# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Client do
  let(:base_url) { 'https://api.example.com' }
  let(:client) { described_class.new(base_url: base_url) }
  let(:endpoint) { '/test' }
  let(:full_url) { "#{base_url}#{endpoint}" }

  describe '#post' do
    context 'when request is successful' do
      it 'returns parsed JSON response for 200 status' do
        response_body = { 'success' => true, 'data' => 'test' }

        stub_request(:post, full_url)
          .to_return(status: 200, body: response_body.to_json)

        result = client.post(endpoint)
        expect(result).to eq(response_body)
      end

      it 'sends correct headers and body' do
        request_body = { 'type' => 'test', 'param' => 'value' }

        stub_request(:post, full_url)
          .with(
            headers: { 'Content-Type' => 'application/json' },
            body: request_body.to_json
          )
          .to_return(status: 200, body: '{}')

        result = client.post(endpoint, request_body)

        expect(result).to eq({})
        expect(a_request(:post, full_url)
          .with(
            headers: { 'Content-Type' => 'application/json' },
            body: request_body.to_json
          )).to have_been_made.once
      end

      it 'handles empty request body' do
        stub_request(:post, full_url)
          .with(body: '')
          .to_return(status: 200, body: '{}')

        result = client.post(endpoint)
        expect(result).to eq({})
      end
    end

    context 'when request fails with client errors' do
      it 'raises BadRequestError for 400 status' do
        stub_request(:post, full_url)
          .to_return(status: 400, body: { 'error' => 'Bad request' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::BadRequestError) do |error|
          expect(error.status_code).to eq(400)
          expect(error.response_body).to eq({ 'error' => 'Bad request' })
        end
      end

      it 'raises AuthenticationError for 401 status' do
        stub_request(:post, full_url)
          .to_return(status: 401, body: { 'error' => 'Unauthorized' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::AuthenticationError) do |error|
          expect(error.status_code).to eq(401)
          expect(error.response_body).to eq({ 'error' => 'Unauthorized' })
        end
      end

      it 'raises NotFoundError for 404 status' do
        stub_request(:post, full_url)
          .to_return(status: 404, body: { 'error' => 'Not found' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::NotFoundError) do |error|
          expect(error.status_code).to eq(404)
          expect(error.response_body).to eq({ 'error' => 'Not found' })
        end
      end

      it 'raises RateLimitError for 429 status' do
        stub_request(:post, full_url)
          .to_return(status: 429, body: { 'error' => 'Rate limit exceeded' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::RateLimitError) do |error|
          expect(error.status_code).to eq(429)
          expect(error.response_body).to eq({ 'error' => 'Rate limit exceeded' })
        end
      end
    end

    context 'when request fails with server errors' do
      it 'raises ServerError for 500 status' do
        stub_request(:post, full_url)
          .to_return(status: 500, body: { 'error' => 'Internal server error' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::ServerError) do |error|
          expect(error.status_code).to eq(500)
          expect(error.response_body).to eq({ 'error' => 'Internal server error' })
        end
      end

      it 'raises ServerError for 503 status' do
        stub_request(:post, full_url)
          .to_return(status: 503, body: { 'error' => 'Service unavailable' }.to_json)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::ServerError) do |error|
          expect(error.status_code).to eq(503)
          expect(error.response_body).to eq({ 'error' => 'Service unavailable' })
        end
      end
    end

    context 'when request fails with unexpected errors' do
      it 'raises ClientError for unexpected status codes' do
        stub_request(:post, full_url)
          .to_return(status: 418, body: "I'm a teapot")

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::ClientError) do |error|
          expect(error.status_code).to eq(418)
          expect(error.response_body).to eq("I'm a teapot")
          expect(error.message).to include('Unexpected response status: 418')
        end
      end
    end

    context 'when network errors occur' do
      it 'raises NetworkError for connection failures' do
        stub_request(:post, full_url).to_raise(Faraday::ConnectionFailed)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::NetworkError) do |error|
          expect(error.message).to include('Connection failed')
        end
      end

      it 'raises TimeoutError for request timeouts' do
        stub_request(:post, full_url).to_raise(Faraday::TimeoutError)

        expect { client.post(endpoint) }.to raise_error(Hyperliquid::TimeoutError) do |error|
          expect(error.message).to include('Request timed out')
        end
      end
    end
  end

  describe 'initialization' do
    it 'creates client with default timeout' do
      client = described_class.new(base_url: base_url)
      expect(client).to be_a(described_class)
    end

    it 'creates client with custom timeout' do
      client = described_class.new(base_url: base_url, timeout: 60)
      expect(client).to be_a(described_class)
    end
  end
end
