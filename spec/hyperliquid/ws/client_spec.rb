# frozen_string_literal: true

RSpec.describe Hyperliquid::WS::Client do
  let(:client) { described_class.new(testnet: false) }
  let(:testnet_client) { described_class.new(testnet: true) }
  let(:noop) { proc { |_d| } }

  # Mock WebSocket object
  let(:mock_ws) do
    ws = instance_double('WebSocket::Client::Simple::Client')
    allow(ws).to receive(:send)
    allow(ws).to receive(:close)
    allow(ws).to receive(:on)
    ws
  end

  before do
    allow(WebSocket::Client::Simple).to receive(:connect).and_return(mock_ws)
  end

  describe '#initialize' do
    it 'creates client with mainnet URL by default' do
      c = described_class.new
      expect(c).not_to be_connected
    end

    it 'creates client with testnet URL when testnet: true' do
      c = described_class.new(testnet: true)
      expect(c).not_to be_connected
    end

    it 'starts disconnected' do
      expect(client).not_to be_connected
    end

    it 'defaults to max queue size of 1024' do
      expect(client.dropped_message_count).to eq(0)
    end
  end

  describe '#subscribe' do
    it 'returns a unique subscription ID' do
      id1 = client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
      id2 = client.subscribe({ type: 'l2Book', coin: 'BTC' }, &noop)
      expect(id1).not_to eq(id2)
    end

    it 'raises ArgumentError without a block' do
      expect { client.subscribe({ type: 'l2Book', coin: 'ETH' }) }.to raise_error(ArgumentError)
    end

    it 'auto-connects when not connected' do
      expect(WebSocket::Client::Simple).to receive(:connect).and_return(mock_ws)
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
    end

    it 'queues subscription when not yet connected' do
      expect(mock_ws).not_to receive(:send)
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
    end

    it 'sends subscribe message when already connected' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      expected_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
      expect(mock_ws).to receive(:send).with(expected_msg)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
    end

    it 'raises WebSocketError for unsupported subscription types' do
      expect do
        client.subscribe({ type: 'unknown', coin: 'ETH' }, &noop)
      end.to raise_error(Hyperliquid::WebSocketError, /Unsupported subscription type/)
    end

    it 'accepts string keys in subscription hash' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      expect(mock_ws).to receive(:send)

      id = client.subscribe({ 'type' => 'l2Book', 'coin' => 'ETH' }, &noop)
      expect(id).to be_a(Integer)
    end
  end

  describe '#unsubscribe' do
    it 'removes callback and sends unsubscribe when last callback removed' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      allow(mock_ws).to receive(:send)

      sub_id = client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)

      unsub_msg = JSON.generate({ method: 'unsubscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
      expect(mock_ws).to receive(:send).with(unsub_msg)

      client.unsubscribe(sub_id)
    end

    it 'does not send unsubscribe when other callbacks remain' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      allow(mock_ws).to receive(:send)

      sub_id1 = client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)

      unsub_msg = JSON.generate({ method: 'unsubscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
      expect(mock_ws).not_to receive(:send).with(unsub_msg)

      client.unsubscribe(sub_id1)
    end

    it 'does nothing for unknown subscription ID' do
      expect { client.unsubscribe(999) }.not_to raise_error
    end
  end

  describe 'message routing' do
    let(:queue) { client.instance_variable_get(:@queue) }

    it 'routes l2Book messages to correct callback by coin' do
      received = []
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }

      msg = { 'channel' => 'l2Book', 'data' => { 'coin' => 'ETH', 'levels' => [] } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('l2Book:eth')
      expect(queued[:data]).to eq({ 'coin' => 'ETH', 'levels' => [] })
    end

    it 'silently discards pong messages' do
      msg = { 'channel' => 'pong' }.to_json
      expect { client.send(:handle_message, msg) }.not_to raise_error
      expect(queue).to be_empty
    end

    it 'silently discards the connection establishment string' do
      expect { client.send(:handle_message, 'Websocket connection established.') }.not_to raise_error
      expect(queue).to be_empty
    end

    it 'handles malformed JSON gracefully' do
      expect { client.send(:handle_message, 'not json {{{') }.not_to raise_error
      expect(queue).to be_empty
    end

    it 'handles nil and empty messages' do
      expect { client.send(:handle_message, nil) }.not_to raise_error
      expect { client.send(:handle_message, '') }.not_to raise_error
      expect(queue).to be_empty
    end

    it 'discards messages with unknown channels' do
      msg = { 'channel' => 'unknownChannel', 'data' => {} }.to_json
      client.send(:handle_message, msg)
      expect(queue).to be_empty
    end
  end

  describe 'message queue and dispatch' do
    it 'messages are dispatched in order to callbacks via the queue' do
      received = []
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d['seq'] }

      client.send(:start_dispatch_thread)

      3.times do |i|
        client.send(:enqueue_message, 'l2Book:eth', { 'seq' => i })
      end

      sleep 0.1

      expect(received).to eq([0, 1, 2])

      client.instance_variable_get(:@queue).close
      client.instance_variable_get(:@dispatch_thread)&.join(1)
    end

    it 'drops messages when queue is full' do
      small_client = described_class.new(max_queue_size: 2)

      small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => 1 })
      small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => 2 })
      small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => 3 })

      expect(small_client.dropped_message_count).to eq(1)
    end

    it 'increments drop counter for each dropped message' do
      small_client = described_class.new(max_queue_size: 1)

      5.times { |i| small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => i }) }

      expect(small_client.dropped_message_count).to eq(4)
    end

    it 'prints warning on first drop' do
      small_client = described_class.new(max_queue_size: 1)

      small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => 0 })
      expect { small_client.send(:enqueue_message, 'l2Book:eth', { 'a' => 1 }) }
        .to output(/Queue full/).to_stderr
    end

    it 'prints warning every 100th drop, not every drop' do
      small_client = described_class.new(max_queue_size: 1)
      small_client.send(:enqueue_message, 'l2Book:eth', { 'fill' => true })

      expect { small_client.send(:enqueue_message, 'l2Book:eth', {}) }
        .to output(/Queue full/).to_stderr

      98.times do
        expect { small_client.send(:enqueue_message, 'l2Book:eth', {}) }
          .not_to output.to_stderr
      end

      expect { small_client.send(:enqueue_message, 'l2Book:eth', {}) }
        .to output(/Queue full/).to_stderr
    end

    it 'multiple callbacks for same channel are all invoked' do
      received1 = []
      received2 = []
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received1 << d }
      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received2 << d }

      client.send(:start_dispatch_thread)
      client.send(:enqueue_message, 'l2Book:eth', { 'coin' => 'ETH' })

      sleep 0.1

      expect(received1).to eq([{ 'coin' => 'ETH' }])
      expect(received2).to eq([{ 'coin' => 'ETH' }])

      client.instance_variable_get(:@queue).close
      client.instance_variable_get(:@dispatch_thread)&.join(1)
    end

    it 'callback errors do not crash the dispatch thread' do
      received = []
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| raise 'boom' }
      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }

      client.send(:start_dispatch_thread)
      client.send(:enqueue_message, 'l2Book:eth', { 'ok' => true })

      sleep 0.1

      expect(received).to eq([{ 'ok' => true }])

      client.instance_variable_get(:@queue).close
      client.instance_variable_get(:@dispatch_thread)&.join(1)
    end
  end

  describe 'ping' do
    it 'ping thread sends ping periodically' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      stub_const('Hyperliquid::Constants::WS_PING_INTERVAL', 0.05)

      ping_msg = JSON.generate({ method: 'ping' })
      expect(mock_ws).to receive(:send).with(ping_msg).at_least(:once)

      client.send(:start_ping_thread)
      sleep 0.15

      client.instance_variable_set(:@closing, true)
      client.instance_variable_get(:@ping_thread)&.kill
    end
  end

  describe 'reconnection' do
    it 'replays subscriptions on reconnect' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)

      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)

      sub_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
      expect(mock_ws).to receive(:send).with(sub_msg)

      client.send(:handle_open)
    end
  end

  describe 'lifecycle' do
    it 'connected? reflects connection state' do
      expect(client).not_to be_connected

      client.instance_variable_set(:@connected, true)
      expect(client).to be_connected

      client.instance_variable_set(:@connected, false)
      expect(client).not_to be_connected
    end

    it 'close stops threads and disconnects' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      client.send(:start_dispatch_thread)
      client.send(:start_ping_thread)

      expect(mock_ws).to receive(:close)

      client.close

      expect(client).not_to be_connected
      expect(client.instance_variable_get(:@ws)).to be_nil
      expect(client.instance_variable_get(:@ping_thread)).to be_nil
      expect(client.instance_variable_get(:@dispatch_thread)).to be_nil
    end

    it 'on registers lifecycle callbacks' do
      opened = false
      client.on(:open) { opened = true }

      client.send(:handle_open)
      expect(opened).to be true
    end

    it 'on(:close) callback fires on close event' do
      closed = false
      client.on(:close) { closed = true }

      client.instance_variable_set(:@closing, true)
      client.send(:handle_close, nil)
      expect(closed).to be true
    end

    it 'on(:error) callback fires on error' do
      error_received = nil
      client.on(:error) { |e| error_received = e }

      err = StandardError.new('test error')
      client.send(:handle_error, err)
      expect(error_received).to eq(err)
    end
  end

  describe 'queued subscriptions flushed on connect' do
    it 'sends queued subscriptions when connection opens' do
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)

      pending = client.instance_variable_get(:@pending_subscriptions)
      expect(pending.length).to eq(1)

      client.instance_variable_set(:@ws, mock_ws)

      sub_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
      expect(mock_ws).to receive(:send).with(sub_msg)

      client.send(:handle_open)

      expect(client.instance_variable_get(:@pending_subscriptions)).to be_empty
    end
  end

  describe '#compute_identifier' do
    it 'computes l2Book identifier' do
      id = client.send(:compute_identifier, 'l2Book', { 'coin' => 'ETH' })
      expect(id).to eq('l2Book:eth')
    end

    it 'computes allMids identifier' do
      id = client.send(:compute_identifier, 'allMids', {})
      expect(id).to eq('allMids')
    end

    it 'computes trades identifier' do
      id = client.send(:compute_identifier, 'trades', [{ 'coin' => 'BTC' }])
      expect(id).to eq('trades:btc')
    end

    it 'returns nil for unknown channel' do
      id = client.send(:compute_identifier, 'someChannel', {})
      expect(id).to be_nil
    end
  end
end
