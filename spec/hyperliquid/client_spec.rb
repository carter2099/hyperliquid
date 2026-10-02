# frozen_string_literal: true

require 'spec_helper'
require 'socket'

RSpec.describe Hyperliquid::Client do
  let(:base_url) { 'https://api.example.com' }
  let(:client) { described_class.new(base_url: base_url) }
  let(:retry_client) { described_class.new(base_url: base_url, retry_enabled: true) }
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

  describe 'retry behavior' do
    let(:max_retries) { described_class::DEFAULT_RETRY_OPTIONS[:max] }
    let(:info_url) { "#{base_url}/info" }
    let(:exchange_url) { "#{base_url}/exchange" }
    let(:sleeps) { [] }

    before do
      recorded = sleeps
      allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep) do |_middleware, seconds|
        recorded << seconds
      end
    end

    it 'retries a transient info failure and returns the eventual success' do
      stub_request(:post, info_url)
        .to_return({ status: 503, body: '{}' }, { status: 200, body: '{"ok":true}' })

      expect(retry_client.post('/info', { type: 'allMids' })).to eq('ok' => true)
      expect(a_request(:post, info_url).with(body: { type: 'allMids' }.to_json)).to have_been_made.times(2)
    end

    it 'retries 429, 502 and 504 on info as well' do
      [429, 502, 504].each do |status|
        WebMock.reset!
        stub_request(:post, info_url).to_return({ status: status, body: '{}' }, { status: 200, body: '{}' })

        expect(retry_client.post('/info')).to eq({})
        expect(a_request(:post, info_url)).to have_been_made.times(2)
      end
    end

    it 'retries an info connection failure' do
      stub_request(:post, info_url).to_raise(Faraday::ConnectionFailed.new('reset')).then
                                   .to_return(status: 200, body: '{}')

      expect(retry_client.post('/info')).to eq({})
      expect(a_request(:post, info_url)).to have_been_made.times(2)
    end

    it 'raises ServerError after max retries with exponential backoff between attempts' do
      stub_request(:post, info_url).to_return(status: 503, body: { 'error' => 'down' }.to_json)

      expect { retry_client.post('/info') }.to raise_error(Hyperliquid::ServerError) do |error|
        expect(error.status_code).to eq(503)
        expect(error.response_body).to eq('error' => 'down')
      end
      expect(a_request(:post, info_url)).to have_been_made.times(max_retries + 1)
      expect(sleeps.size).to eq(max_retries)
      expect(sleeps[0]).to be_between(0.5, 0.75)
      expect(sleeps[1]).to be_between(1.0, 1.25)
    end

    it 'never retries /exchange, even on a retryable status' do
      stub_request(:post, exchange_url).to_return(status: 503, body: '{}')

      expect { retry_client.post('/exchange', { action: { type: 'noop' } }) }.to raise_error(Hyperliquid::ServerError)
      expect(a_request(:post, exchange_url)).to have_been_made.once
      expect(sleeps).to be_empty
    end

    it 'never retries /exchange on a connection failure' do
      stub_request(:post, exchange_url).to_raise(Faraday::ConnectionFailed.new('reset'))

      expect { retry_client.post('/exchange', { action: { type: 'noop' } }) }.to raise_error(Hyperliquid::NetworkError)
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end

    it 'does not retry info when retries are disabled (the default)' do
      stub_request(:post, info_url).to_return({ status: 503, body: '{}' }, { status: 200, body: '{}' })

      expect { client.post('/info') }.to raise_error(Hyperliquid::ServerError)
      expect(a_request(:post, info_url)).to have_been_made.once
    end

    it 'does not retry statuses outside the retry list' do
      { 400 => Hyperliquid::BadRequestError, 401 => Hyperliquid::AuthenticationError,
        404 => Hyperliquid::NotFoundError, 500 => Hyperliquid::ServerError }.each do |status, error_class|
        WebMock.reset!
        stub_request(:post, info_url).to_return(status: status, body: '{}')

        expect { retry_client.post('/info') }.to raise_error(error_class)
        expect(a_request(:post, info_url)).to have_been_made.once
      end
    end
  end

  describe 'timeout' do
    around do |example|
      config = WebMock::Config.instance
      fields = %i[allow_net_connect allow_localhost allow net_http_connect_on_start]
      saved = fields.to_h { |field| [field, config.public_send(field)] }
      WebMock.disable_net_connect!(allow_localhost: true)
      example.run
    ensure
      saved&.each { |field, value| config.public_send(:"#{field}=", value) }
    end

    it 'applies the configured timeout to reads from a server that never answers' do
      server = TCPServer.new('127.0.0.1', 0)
      acceptor = Thread.new do
        socket = server.accept
        sleep 5
        socket.close
      end
      slow_client = described_class.new(base_url: "http://127.0.0.1:#{server.addr[1]}", timeout: 0.3)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { slow_client.post('/info', { type: 'allMids' }) }.to raise_error(Hyperliquid::TimeoutError)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    ensure
      acceptor&.kill
      server&.close
    end
  end

  describe 'explorer target routing' do
    let(:explorer_base_url) { 'https://rpc.example.com' }
    let(:explorer_endpoint) { '/explorer' }
    let(:explorer_url) { "#{explorer_base_url}#{explorer_endpoint}" }
    let(:explorer_client) do
      described_class.new(base_url: base_url, explorer_base_url: explorer_base_url)
    end

    it 'routes target: :explorer to the explorer base URL' do
      stub_request(:post, explorer_url)
        .with(body: { type: 'txDetails', hash: '0xabc' }.to_json)
        .to_return(status: 200, body: { 'type' => 'txDetails', 'tx' => {} }.to_json)

      result = explorer_client.post(explorer_endpoint, { type: 'txDetails', hash: '0xabc' }, target: :explorer)
      expect(result).to eq('type' => 'txDetails', 'tx' => {})
      expect(a_request(:post, explorer_url)).to have_been_made.once
    end

    it 'routes target: :default to the default base URL' do
      stub_request(:post, full_url).to_return(status: 200, body: '{}')
      explorer_client.post(endpoint)
      expect(a_request(:post, full_url)).to have_been_made.once
    end

    it 'lazily builds the explorer connection (not allocated until first explorer call)' do
      expect(explorer_client.instance_variable_get(:@explorer_connection)).to be_nil

      stub_request(:post, explorer_url).to_return(status: 200, body: '{}')
      explorer_client.post(explorer_endpoint, { type: 'txDetails', hash: '0x' }, target: :explorer)

      expect(explorer_client.instance_variable_get(:@explorer_connection)).not_to be_nil
    end

    it 'reuses the same explorer connection across calls' do
      stub_request(:post, explorer_url).to_return(status: 200, body: '{}')
      explorer_client.post(explorer_endpoint, { type: 'a' }, target: :explorer)
      first = explorer_client.instance_variable_get(:@explorer_connection)
      explorer_client.post(explorer_endpoint, { type: 'b' }, target: :explorer)
      expect(explorer_client.instance_variable_get(:@explorer_connection)).to be(first)
    end

    it 'raises ConfigurationError when explorer URL is not configured' do
      no_explorer_client = described_class.new(base_url: base_url)
      expect do
        no_explorer_client.post(explorer_endpoint, { type: 'txDetails' }, target: :explorer)
      end.to raise_error(Hyperliquid::ConfigurationError, /Explorer RPC URL not configured/)
    end

    it 'raises ArgumentError on unknown target' do
      expect { explorer_client.post(endpoint, {}, target: :other) }
        .to raise_error(ArgumentError, /Unknown post target/)
    end

    it 'retries explorer reads when retries are enabled' do
      allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep)
      retry_explorer_client = described_class.new(
        base_url: base_url, explorer_base_url: explorer_base_url, retry_enabled: true
      )
      stub_request(:post, explorer_url)
        .to_return({ status: 503, body: '{}' }, { status: 200, body: '{"type":"txDetails"}' })

      result = retry_explorer_client.post(explorer_endpoint, { type: 'txDetails' }, target: :explorer)

      expect(result).to eq('type' => 'txDetails')
      expect(a_request(:post, explorer_url)).to have_been_made.times(2)
    end

    it 'translates Faraday::ConnectionFailed on explorer to NetworkError' do
      stub_request(:post, explorer_url).to_raise(Faraday::ConnectionFailed.new('boom'))
      expect do
        explorer_client.post(explorer_endpoint, { type: 'a' }, target: :explorer)
      end.to raise_error(Hyperliquid::NetworkError, /Connection failed/)
    end
  end
end
