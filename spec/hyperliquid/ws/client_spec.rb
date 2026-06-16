# frozen_string_literal: true

RSpec.describe Hyperliquid::WS::Client do
  let(:client) { described_class.new(testnet: false) }
  let(:testnet_client) { described_class.new(testnet: true) }
  let(:noop) { proc { |_d| } }

  # Mock WebSocket object
  let(:mock_ws) do
    ws = instance_double('WSLite::Client')
    allow(ws).to receive(:send)
    allow(ws).to receive(:close)
    allow(ws).to receive(:on)
    ws
  end

  before do
    allow(WSLite).to receive(:connect).and_return(mock_ws)
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
      expect(WSLite).to receive(:connect).and_return(mock_ws)
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

  describe 'stale connection guard' do
    it 'ignores handle_close from a superseded connection' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@connection_id, 2)

      # Simulate a stale callback from connection_id=1
      expect(client.send(:stale_connection?, 1)).to be true
      expect(client.send(:stale_connection?, 2)).to be false
    end

    it 'does not set connected=false when stale close fires' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@connection_id, 2)

      # A stale close should not affect the current connection state
      # (The guard is in the closure, so we test via stale_connection? directly)
      expect(client.send(:stale_connection?, 1)).to be true
      expect(client).to be_connected
    end

    it 'increments connection_id on each establish_connection call' do
      initial_id = client.instance_variable_get(:@connection_id)

      client.send(:establish_connection)
      expect(client.instance_variable_get(:@connection_id)).to eq(initial_id + 1)

      client.send(:establish_connection)
      expect(client.instance_variable_get(:@connection_id)).to eq(initial_id + 2)
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
      expect(client.send(:compute_identifier, 'l2Book', { 'coin' => 'ETH' })).to eq('l2Book:eth')
    end

    it 'computes allMids identifier' do
      expect(client.send(:compute_identifier, 'allMids', {})).to eq('allMids')
    end

    it 'computes trades identifier' do
      expect(client.send(:compute_identifier, 'trades', [{ 'coin' => 'BTC' }])).to eq('trades:btc')
    end

    it 'computes bbo identifier' do
      expect(client.send(:compute_identifier, 'bbo', { 'coin' => 'SOL' })).to eq('bbo:sol')
    end

    it 'computes candle identifier' do
      expect(client.send(:compute_identifier, 'candle', { 's' => 'ETH', 'i' => '1h' })).to eq('candle:eth:1h')
    end

    it 'computes orderUpdates identifier' do
      expect(client.send(:compute_identifier, 'orderUpdates', [])).to eq('orderUpdates')
    end

    it 'computes userEvents identifier' do
      data = { 'user' => '0xAbC123', 'fills' => [] }
      expect(client.send(:compute_identifier, 'userEvents', data)).to eq('userEvents:0xabc123')
    end

    it 'computes userFills identifier' do
      data = { 'user' => '0xAbC123', 'fills' => [] }
      expect(client.send(:compute_identifier, 'userFills', data)).to eq('userFills:0xabc123')
    end

    it 'computes userFundings identifier' do
      data = { 'user' => '0xAbC123', 'fundings' => [] }
      expect(client.send(:compute_identifier, 'userFundings', data)).to eq('userFundings:0xabc123')
    end

    it 'returns nil for unknown channel' do
      expect(client.send(:compute_identifier, 'someChannel', {})).to be_nil
    end

    it 'returns nil for trades with empty array' do
      expect(client.send(:compute_identifier, 'trades', [])).to be_nil
    end
  end

  describe '#subscription_identifier' do
    it 'computes l2Book subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'l2Book', coin: 'ETH' })).to eq('l2Book:eth')
    end

    it 'computes allMids subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'allMids' })).to eq('allMids')
    end

    it 'computes trades subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'trades', coin: 'BTC' })).to eq('trades:btc')
    end

    it 'computes bbo subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'bbo', coin: 'SOL' })).to eq('bbo:sol')
    end

    it 'computes candle subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'candle', coin: 'ETH', interval: '15m' }))
        .to eq('candle:eth:15m')
    end

    it 'computes orderUpdates subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'orderUpdates', user: '0xABC' }))
        .to eq('orderUpdates')
    end

    it 'computes userEvents subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'userEvents', user: '0xABC' }))
        .to eq('userEvents:0xabc')
    end

    it 'computes userFills subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'userFills', user: '0xABC' }))
        .to eq('userFills:0xabc')
    end

    it 'computes userFundings subscription identifier' do
      expect(client.send(:subscription_identifier, { type: 'userFundings', user: '0xABC' }))
        .to eq('userFundings:0xabc')
    end

    it 'supports string keys' do
      expect(client.send(:subscription_identifier, { 'type' => 'bbo', 'coin' => 'ETH' })).to eq('bbo:eth')
    end

    it 'raises for unsupported type' do
      expect do
        client.send(:subscription_identifier, { type: 'badType' })
      end.to raise_error(Hyperliquid::WebSocketError)
    end
  end

  describe 'channel message routing' do
    let(:queue) { client.instance_variable_get(:@queue) }

    before do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      allow(mock_ws).to receive(:send)
    end

    it 'routes allMids messages' do
      client.subscribe({ type: 'allMids' }) { |d| d }
      msg = { 'channel' => 'allMids', 'data' => { 'mids' => { 'ETH' => '3000' } } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('allMids')
      expect(queued[:data]['mids']['ETH']).to eq('3000')
    end

    it 'routes trades messages' do
      client.subscribe({ type: 'trades', coin: 'BTC' }) { |d| d }
      msg = { 'channel' => 'trades', 'data' => [{ 'coin' => 'BTC', 'px' => '50000' }] }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('trades:btc')
    end

    it 'routes bbo messages' do
      client.subscribe({ type: 'bbo', coin: 'SOL' }) { |d| d }
      msg = { 'channel' => 'bbo', 'data' => { 'coin' => 'SOL', 'bid' => '100' } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('bbo:sol')
    end

    it 'routes candle messages' do
      client.subscribe({ type: 'candle', coin: 'ETH', interval: '1h' }) { |d| d }
      msg = { 'channel' => 'candle', 'data' => { 's' => 'ETH', 'i' => '1h', 'o' => '3000' } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('candle:eth:1h')
    end

    it 'routes orderUpdates messages' do
      client.subscribe({ type: 'orderUpdates', user: '0xABC' }) { |d| d }
      msg = { 'channel' => 'orderUpdates', 'data' => [{ 'order' => { 'coin' => 'ETH' } }] }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('orderUpdates')
    end

    it 'routes userEvents messages' do
      user = '0xabc123'
      client.subscribe({ type: 'userEvents', user: user }) { |d| d }
      msg = { 'channel' => 'userEvents', 'data' => { 'user' => user, 'fills' => [] } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq("userEvents:#{user}")
    end

    it 'routes userFills messages' do
      user = '0xdef456'
      client.subscribe({ type: 'userFills', user: user }) { |d| d }
      msg = { 'channel' => 'userFills', 'data' => { 'user' => user, 'fills' => [] } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq("userFills:#{user}")
    end

    it 'routes userFundings messages' do
      user = '0xfff789'
      client.subscribe({ type: 'userFundings', user: user }) { |d| d }
      msg = { 'channel' => 'userFundings', 'data' => { 'user' => user, 'fundings' => [] } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq("userFundings:#{user}")
    end

    it 'does not cross-route between different coins on same channel' do
      client.subscribe({ type: 'bbo', coin: 'ETH' }) { |d| d }
      msg = { 'channel' => 'bbo', 'data' => { 'coin' => 'SOL', 'bid' => '100' } }.to_json
      client.send(:handle_message, msg)

      # Message was enqueued under bbo:sol, but we subscribed to bbo:eth -- no match on dispatch
      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('bbo:sol')
    end

    it 'does not cross-route candle messages with different intervals' do
      client.subscribe({ type: 'candle', coin: 'ETH', interval: '1h' }) { |d| d }
      msg = { 'channel' => 'candle', 'data' => { 's' => 'ETH', 'i' => '15m', 'o' => '3000' } }.to_json
      client.send(:handle_message, msg)

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('candle:eth:15m')
    end
  end

  # ── Explorer WebSocket ──────────────────────────────────────────

  describe 'explorer WebSocket' do
    let(:explorer_client) do
      described_class.new(
        testnet: false,
        explorer_ws_url: 'wss://rpc.hyperliquid.xyz/ws'
      )
    end

    let(:mock_explorer_ws) do
      ws = instance_double('WSLite::Client')
      allow(ws).to receive(:send)
      allow(ws).to receive(:close)
      allow(ws).to receive(:on)
      ws
    end

    describe 'initialization' do
      it 'stores explorer_ws_url when provided' do
        c = described_class.new(explorer_ws_url: 'wss://rpc.hyperliquid.xyz/ws')
        expect(c.instance_variable_get(:@explorer_ws_url)).to eq('wss://rpc.hyperliquid.xyz/ws')
      end

      it 'initializes explorer ivars to nil/false/empty' do
        c = described_class.new(explorer_ws_url: 'wss://rpc.hyperliquid.xyz/ws')
        expect(c.instance_variable_get(:@explorer_ws)).to be_nil
        expect(c.instance_variable_get(:@explorer_connected)).to be false
        expect(c.instance_variable_get(:@explorer_closing)).to be false
        expect(c.instance_variable_get(:@explorer_subscriptions)).to eq({})
        expect(c.instance_variable_get(:@explorer_subscription_msgs)).to eq({})
        expect(c.instance_variable_get(:@explorer_next_id)).to eq(0)
        expect(c.instance_variable_get(:@explorer_pending_subscriptions)).to eq([])
      end

      it 'defaults explorer_ws_url to nil when not provided' do
        c = described_class.new
        expect(c.instance_variable_get(:@explorer_ws_url)).to be_nil
      end

      it 'explorer_dropped_message_count starts at 0' do
        expect(explorer_client.explorer_dropped_message_count).to eq(0)
      end
    end

    describe '#subscribe_explorer_block' do
      it 'raises ArgumentError without a block' do
        expect { explorer_client.subscribe_explorer_block }.to raise_error(ArgumentError)
      end

      it 'raises ConfigurationError without explorer_ws_url configured' do
        c = described_class.new(testnet: false)
        expect { c.subscribe_explorer_block { |_d| } }.to raise_error(Hyperliquid::ConfigurationError)
      end

      it 'returns a unique subscription ID' do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
        id1 = explorer_client.subscribe_explorer_block { |_d| }
        id2 = explorer_client.subscribe_explorer_block { |_d| }
        expect(id1).to be_a(Integer)
        expect(id2).to be_a(Integer)
        expect(id1).not_to eq(id2)
      end

      it 'auto-connects explorer WS when not connected' do
        expect(WSLite).to receive(:connect).with('wss://rpc.hyperliquid.xyz/ws').and_return(mock_explorer_ws)
        explorer_client.subscribe_explorer_block { |_d| }
      end

      it 'queues subscription when not yet connected' do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
        explorer_client.subscribe_explorer_block { |_d| }
        pending = explorer_client.instance_variable_get(:@explorer_pending_subscriptions)
        expect(pending).to include({ type: 'explorerBlock' })
      end

      it 'sends subscribe message when already connected' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        expected_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).to receive(:send).with(expected_msg)

        explorer_client.subscribe_explorer_block { |_d| }
      end
    end

    describe '#subscribe_explorer_txs' do
      it 'raises ArgumentError without a block' do
        expect { explorer_client.subscribe_explorer_txs }.to raise_error(ArgumentError)
      end

      it 'raises ConfigurationError without explorer_ws_url configured' do
        c = described_class.new(testnet: false)
        expect { c.subscribe_explorer_txs { |_d| } }.to raise_error(Hyperliquid::ConfigurationError)
      end

      it 'returns a unique subscription ID' do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
        id = explorer_client.subscribe_explorer_txs { |_d| }
        expect(id).to be_a(Integer)
      end

      it 'sends correct subscribe message when connected' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        expected_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'explorerTxs' } })
        expect(mock_explorer_ws).to receive(:send).with(expected_msg)

        explorer_client.subscribe_explorer_txs { |_d| }
      end
    end

    describe 'explorer message handling' do
      let(:explorer_queue) { explorer_client.instance_variable_get(:@explorer_queue) }

      it 'routes explorerBlock bare arrays to explorerBlock identifier' do
        block_data = [{
          'blockTime' => 1_717_000_000_000,
          'hash' => '0xabc123',
          'height' => 12_345_678,
          'numTxs' => 42,
          'proposer' => '0xdef456'
        }]

        explorer_client.send(:handle_explorer_message, block_data.to_json)

        queued = explorer_queue.pop(true)
        expect(queued[:identifier]).to eq('explorerBlock')
        expect(queued[:data]).to eq(block_data)
      end

      it 'routes explorerTxs bare arrays to explorerTxs identifier' do
        tx_data = [{
          'action' => { 'type' => 'order' },
          'block' => 12_345_678,
          'error' => nil,
          'hash' => '0xabc123',
          'time' => 1_717_000_000_000,
          'user' => '0xdef456'
        }]

        explorer_client.send(:handle_explorer_message, tx_data.to_json)

        queued = explorer_queue.pop(true)
        expect(queued[:identifier]).to eq('explorerTxs')
        expect(queued[:data]).to eq(tx_data)
      end

      it 'receives the full array (not a single element)' do
        block_data = [
          { 'blockTime' => 1, 'hash' => '0xa', 'height' => 1, 'numTxs' => 1, 'proposer' => '0x1' },
          { 'blockTime' => 2, 'hash' => '0xb', 'height' => 2, 'numTxs' => 2, 'proposer' => '0x2' }
        ]

        explorer_client.send(:handle_explorer_message, block_data.to_json)

        queued = explorer_queue.pop(true)
        expect(queued[:data]).to eq(block_data)
        expect(queued[:data].length).to eq(2)
      end

      it 'warns on unknown explorer WS array shape' do
        unknown_data = [{ 'unknown_field' => 'value' }]

        expect do
          explorer_client.send(:handle_explorer_message, unknown_data.to_json)
        end.to output(/Unknown explorer WS array shape/).to_stderr

        expect(explorer_queue).to be_empty
      end

      it 'silently discards pong messages' do
        pong = { 'channel' => 'pong' }.to_json
        expect { explorer_client.send(:handle_explorer_message, pong) }.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards other hash messages' do
        msg = { 'channel' => 'someOther', 'data' => {} }.to_json
        expect { explorer_client.send(:handle_explorer_message, msg) }.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards nil messages' do
        expect { explorer_client.send(:handle_explorer_message, nil) }.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards empty messages' do
        expect { explorer_client.send(:handle_explorer_message, '') }.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards "Websocket connection established" messages' do
        expect do
          explorer_client.send(:handle_explorer_message, 'Websocket connection established')
        end.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'handles malformed JSON gracefully' do
        expect do
          explorer_client.send(:handle_explorer_message, 'not json {{{')
        end.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards empty arrays' do
        expect { explorer_client.send(:handle_explorer_message, '[]') }.not_to raise_error
        expect(explorer_queue).to be_empty
      end

      it 'discards non-array non-hash JSON' do
        expect do
          explorer_client.send(:handle_explorer_message, '"just a string"')
        end.not_to raise_error
        expect(explorer_queue).to be_empty
      end
    end

    describe 'isolation between main and explorer WS' do
      let(:main_queue) { explorer_client.instance_variable_get(:@queue) }
      let(:explorer_queue) { explorer_client.instance_variable_get(:@explorer_queue) }

      before do
        explorer_client.instance_variable_set(:@connected, true)
        explorer_client.instance_variable_set(:@ws, mock_ws)
        allow(mock_ws).to receive(:send)
      end

      it 'explorer messages do not route to main-API WS callbacks' do
        main_received = []
        explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| main_received << d }

        block_data = [{
          'blockTime' => 1, 'hash' => '0xa', 'height' => 1, 'numTxs' => 1, 'proposer' => '0x1'
        }]
        explorer_client.send(:handle_explorer_message, block_data.to_json)

        # Main queue should be empty — explorer messages go to explorer queue
        expect(main_queue).to be_empty
        expect(explorer_queue.size).to eq(1)
      end

      it 'main-API WS messages do not route to explorer callbacks' do
        explorer_received = []
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
        explorer_client.subscribe_explorer_block { |d| explorer_received << d }

        l2_msg = { 'channel' => 'l2Book', 'data' => { 'coin' => 'ETH', 'levels' => [] } }.to_json
        explorer_client.send(:handle_message, l2_msg)

        # Explorer queue should be empty — main messages go to main queue
        expect(explorer_queue).to be_empty
        expect(main_queue.size).to eq(1)
      end

      it 'handle_message still works for all existing channel types after explorer code added' do
        explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
        explorer_client.subscribe({ type: 'allMids' }) { |_d| }
        explorer_client.subscribe({ type: 'trades', coin: 'BTC' }) { |_d| }
        explorer_client.subscribe({ type: 'bbo', coin: 'SOL' }) { |_d| }
        explorer_client.subscribe({ type: 'candle', coin: 'ETH', interval: '1h' }) { |_d| }
        explorer_client.subscribe({ type: 'orderUpdates', user: '0xABC' }) { |_d| }
        explorer_client.subscribe({ type: 'userEvents', user: '0xABC' }) { |_d| }
        explorer_client.subscribe({ type: 'userFills', user: '0xABC' }) { |_d| }
        explorer_client.subscribe({ type: 'userFundings', user: '0xABC' }) { |_d| }

        # Each channel should route correctly
        channels = [
          { 'channel' => 'l2Book', 'data' => { 'coin' => 'ETH', 'levels' => [] } },
          { 'channel' => 'allMids', 'data' => { 'mids' => {} } },
          { 'channel' => 'trades', 'data' => [{ 'coin' => 'BTC' }] },
          { 'channel' => 'bbo', 'data' => { 'coin' => 'SOL', 'bid' => '100' } },
          { 'channel' => 'candle', 'data' => { 's' => 'ETH', 'i' => '1h' } },
          { 'channel' => 'orderUpdates', 'data' => [] },
          { 'channel' => 'userEvents', 'data' => { 'user' => '0xABC' } },
          { 'channel' => 'userFills', 'data' => { 'user' => '0xABC' } },
          { 'channel' => 'userFundings', 'data' => { 'user' => '0xABC' } }
        ]

        channels.each do |msg|
          explorer_client.send(:handle_message, msg.to_json)
        end

        expect(main_queue.size).to eq(9)
        expect(explorer_queue).to be_empty
      end

      it 'compute_identifier returns correct values for all existing channels' do
        expect(explorer_client.send(:compute_identifier, 'l2Book', { 'coin' => 'ETH' })).to eq('l2Book:eth')
        expect(explorer_client.send(:compute_identifier, 'allMids', {})).to eq('allMids')
        expect(explorer_client.send(:compute_identifier, 'trades', [{ 'coin' => 'BTC' }])).to eq('trades:btc')
        expect(explorer_client.send(:compute_identifier, 'bbo', { 'coin' => 'SOL' })).to eq('bbo:sol')
        expect(explorer_client.send(:compute_identifier, 'candle', { 's' => 'ETH', 'i' => '1h' }))
          .to eq('candle:eth:1h')
        expect(explorer_client.send(:compute_identifier, 'orderUpdates', [])).to eq('orderUpdates')
        expect(explorer_client.send(:compute_identifier, 'userEvents', { 'user' => '0xABC' }))
          .to eq('userEvents:0xabc')
        expect(explorer_client.send(:compute_identifier, 'userFills', { 'user' => '0xABC' }))
          .to eq('userFills:0xabc')
        expect(explorer_client.send(:compute_identifier, 'userFundings', { 'user' => '0xABC' }))
          .to eq('userFundings:0xabc')
      end

      it 'subscription_identifier still raises for unknown types (explorer types use separate entry points)' do
        expect do
          explorer_client.send(:subscription_identifier, { type: 'explorerBlock' })
        end.to raise_error(Hyperliquid::WebSocketError, /Unsupported subscription type/)
      end
    end

    describe 'explorer subscription management' do
      before do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
      end

      it 'subscription IDs are independent from main-API IDs' do
        main_id = explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
        explorer_id = explorer_client.subscribe_explorer_block { |_d| }

        # Both start from 0 but are in separate namespaces
        expect(main_id).to eq(0)
        expect(explorer_id).to eq(0)
      end

      it 'supports multiple callbacks for the same explorer channel' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_explorer_ws).to receive(:send)

        id1 = explorer_client.subscribe_explorer_block { |_d| }
        id2 = explorer_client.subscribe_explorer_block { |_d| }

        expect(id1).not_to eq(id2)
        callbacks = explorer_client.instance_variable_get(:@explorer_subscriptions)['explorerBlock']
        expect(callbacks.length).to eq(2)
      end

      it 'unsubscribe works for explorer subscription IDs' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_explorer_ws).to receive(:send)

        sub_id = explorer_client.subscribe_explorer_block { |_d| }

        unsub_msg = JSON.generate({ method: 'unsubscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).to receive(:send).with(unsub_msg)

        explorer_client.unsubscribe(sub_id)
      end

      it 'unsubscribe does not send wire message when other callbacks remain' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_explorer_ws).to receive(:send)

        id1 = explorer_client.subscribe_explorer_block { |_d| }
        explorer_client.subscribe_explorer_block { |_d| }

        unsub_msg = JSON.generate({ method: 'unsubscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).not_to receive(:send).with(unsub_msg)

        explorer_client.unsubscribe(id1)
      end

      it 'unsubscribe still works for main-API subscription IDs' do
        explorer_client.instance_variable_set(:@connected, true)
        explorer_client.instance_variable_set(:@ws, mock_ws)
        allow(mock_ws).to receive(:send)

        sub_id = explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }

        unsub_msg = JSON.generate({ method: 'unsubscribe', subscription: { type: 'l2Book', coin: 'ETH' } })
        expect(mock_ws).to receive(:send).with(unsub_msg)

        explorer_client.unsubscribe(sub_id)
      end
    end

    describe 'explorer queue and dispatch' do
      before do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)
      end

      it 'drops messages when explorer queue is full' do
        small_client = described_class.new(max_queue_size: 2, explorer_ws_url: 'wss://rpc.hyperliquid.xyz/ws')

        small_client.send(:enqueue_explorer_message, 'explorerBlock', { 'a' => 1 })
        small_client.send(:enqueue_explorer_message, 'explorerBlock', { 'a' => 2 })
        small_client.send(:enqueue_explorer_message, 'explorerBlock', { 'a' => 3 })

        expect(small_client.explorer_dropped_message_count).to eq(1)
      end

      it 'dispatches messages in order to callbacks' do
        received = []
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        explorer_client.subscribe_explorer_block { |d| received << d['height'] }

        explorer_client.send(:start_explorer_dispatch_thread)

        3.times do |i|
          explorer_client.send(:enqueue_explorer_message, 'explorerBlock', { 'height' => i })
        end

        sleep 0.1

        expect(received).to eq([0, 1, 2])

        explorer_client.instance_variable_get(:@explorer_queue).close
        explorer_client.instance_variable_get(:@explorer_dispatch_thread)&.join(1)
      end

      it 'callback errors do not crash the explorer dispatch thread' do
        received = []
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        explorer_client.subscribe_explorer_block { |_d| raise 'boom' }
        explorer_client.subscribe_explorer_block { |d| received << d }

        explorer_client.send(:start_explorer_dispatch_thread)
        explorer_client.send(:enqueue_explorer_message, 'explorerBlock', { 'ok' => true })

        sleep 0.1

        expect(received).to eq([{ 'ok' => true }])

        explorer_client.instance_variable_get(:@explorer_queue).close
        explorer_client.instance_variable_get(:@explorer_dispatch_thread)&.join(1)
      end

      it 'multiple callbacks for same explorer channel are all invoked' do
        received1 = []
        received2 = []
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        explorer_client.subscribe_explorer_block { |d| received1 << d }
        explorer_client.subscribe_explorer_block { |d| received2 << d }

        explorer_client.send(:start_explorer_dispatch_thread)
        explorer_client.send(:enqueue_explorer_message, 'explorerBlock', { 'height' => 1 })

        sleep 0.1

        expect(received1).to eq([{ 'height' => 1 }])
        expect(received2).to eq([{ 'height' => 1 }])

        explorer_client.instance_variable_get(:@explorer_queue).close
        explorer_client.instance_variable_get(:@explorer_dispatch_thread)&.join(1)
      end
    end

    describe 'explorer ping' do
      it 'ping thread sends ping periodically' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        stub_const('Hyperliquid::Constants::WS_PING_INTERVAL', 0.05)

        ping_msg = JSON.generate({ method: 'ping' })
        expect(mock_explorer_ws).to receive(:send).with(ping_msg).at_least(:once)

        explorer_client.send(:start_explorer_ping_thread)
        sleep 0.15

        explorer_client.instance_variable_set(:@explorer_closing, true)
        explorer_client.instance_variable_get(:@explorer_ping_thread)&.kill
      end
    end

    describe 'explorer reconnection' do
      it 'replays explorer subscriptions on reconnect' do
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_explorer_ws).to receive(:send)

        explorer_client.subscribe_explorer_block { |_d| }

        sub_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).to receive(:send).with(sub_msg)

        explorer_client.send(:handle_explorer_open)
      end

      it 'stale explorer connection guard works' do
        explorer_client.instance_variable_set(:@explorer_connection_id, 2)

        expect(explorer_client.send(:stale_explorer_connection?, 1)).to be true
        expect(explorer_client.send(:stale_explorer_connection?, 2)).to be false
      end

      it 'increments explorer_connection_id on each establish call' do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)

        initial_id = explorer_client.instance_variable_get(:@explorer_connection_id)

        explorer_client.send(:establish_explorer_connection)
        expect(explorer_client.instance_variable_get(:@explorer_connection_id)).to eq(initial_id + 1)

        explorer_client.send(:establish_explorer_connection)
        expect(explorer_client.instance_variable_get(:@explorer_connection_id)).to eq(initial_id + 2)
      end

      it 'handle_explorer_close triggers reconnect when not closing' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        allow(Thread).to receive(:new).and_call_original

        expect(Thread).to receive(:new).and_return(Thread.new { nil })
        explorer_client.send(:handle_explorer_close, nil)
      end

      it 'handle_explorer_close does not reconnect when closing' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_closing, true)

        expect(Thread).not_to receive(:new)
        explorer_client.send(:handle_explorer_close, nil)
      end
    end

    describe 'explorer lifecycle' do
      it 'explorer_connected? reflects connection state' do
        expect(explorer_client).not_to be_explorer_connected

        explorer_client.instance_variable_set(:@explorer_connected, true)
        expect(explorer_client).to be_explorer_connected

        explorer_client.instance_variable_set(:@explorer_connected, false)
        expect(explorer_client).not_to be_explorer_connected
      end

      it 'close tears down both connections' do
        explorer_client.instance_variable_set(:@connected, true)
        explorer_client.instance_variable_set(:@ws, mock_ws)
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        expect(mock_ws).to receive(:close)
        expect(mock_explorer_ws).to receive(:close)

        explorer_client.close

        expect(explorer_client).not_to be_connected
        expect(explorer_client).not_to be_explorer_connected
        expect(explorer_client.instance_variable_get(:@ws)).to be_nil
        expect(explorer_client.instance_variable_get(:@explorer_ws)).to be_nil
      end

      it 'close kills both ping threads and both dispatch threads' do
        explorer_client.instance_variable_set(:@ws, mock_ws)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        explorer_client.send(:start_dispatch_thread)
        explorer_client.send(:start_ping_thread)
        explorer_client.send(:start_explorer_dispatch_thread)
        explorer_client.send(:start_explorer_ping_thread)

        explorer_client.close

        expect(explorer_client.instance_variable_get(:@ping_thread)).to be_nil
        expect(explorer_client.instance_variable_get(:@explorer_ping_thread)).to be_nil
        expect(explorer_client.instance_variable_get(:@dispatch_thread)).to be_nil
        expect(explorer_client.instance_variable_get(:@explorer_dispatch_thread)).to be_nil
      end

      it '@explorer_closing prevents spurious reconnect' do
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.close

        expect(explorer_client.instance_variable_get(:@explorer_closing)).to be true
      end
    end

    describe 'explorer queued subscriptions flushed on connect' do
      it 'sends queued explorer subscriptions when connection opens' do
        allow(WSLite).to receive(:connect).and_return(mock_explorer_ws)

        explorer_client.subscribe_explorer_block { |_d| }

        pending = explorer_client.instance_variable_get(:@explorer_pending_subscriptions)
        expect(pending.length).to eq(1)

        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        sub_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).to receive(:send).with(sub_msg)

        explorer_client.send(:handle_explorer_open)

        expect(explorer_client.instance_variable_get(:@explorer_pending_subscriptions)).to be_empty
      end
    end
  end
end
