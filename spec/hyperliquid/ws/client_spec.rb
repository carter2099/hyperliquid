# frozen_string_literal: true

require 'spec_helper'
require 'zlib'

# Stands in for WSLite::Client: records the handlers WS::Client registers in its
# establish_*_connection block and the frames it sends, so specs can drive socket events.
class FakeWSLiteSocket
  Message = Struct.new(:data)

  attr_reader :url, :sent

  def initialize(url)
    @url = url
    @handlers = {}
    @sent = []
    @closed = false
  end

  def on(event, &handler)
    @handlers[event] = handler
  end

  def send(data)
    @sent << data
  end

  def sent_json
    @sent.map { |frame| JSON.parse(frame) }
  end

  # Client-initiated close: ws_lite emits its internal :__close, then :close.
  def close
    return if @closed

    @closed = true
    emit(:__close)
    emit(:close)
  end

  # Server-initiated close / network drop: ws_lite 1.0.1 emits only :__close (its read thread
  # kills itself before emitting :close).
  def drop!
    @closed = true
    emit(:__close)
  end

  def emit(event, arg = nil)
    @handlers.fetch(event).call(arg)
  end

  # Like ws_lite's read loop: an exception raised by the :message handler is re-emitted as :error.
  def receive(text)
    emit(:message, Message.new(text))
  rescue StandardError => e
    emit(:error, e)
  end
end

RSpec.describe Hyperliquid::WS::Client do
  let(:client) { described_class.new(testnet: false) }
  let(:testnet_client) { described_class.new(testnet: true) }
  let(:noop) { proc { |_d| } }
  let(:created_clients) { [] }

  # Mock WebSocket object
  let(:mock_ws) do
    ws = instance_double(WSLite::Client)
    allow(ws).to receive(:send)
    allow(ws).to receive(:close)
    allow(ws).to receive(:on)
    ws
  end

  before do
    allow(WSLite).to receive(:connect).and_return(mock_ws)
    allow(described_class).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap { |c| created_clients << c }
    end
  end

  # Stops the dispatch/ping threads any example started.
  after { created_clients.each(&:close) }

  describe '#initialize' do
    it 'starts disconnected' do
      expect(client).not_to be_connected
    end

    it 'defaults to a 1024-message queue, dropping the 1025th' do
      1024.times { |i| client.send(:enqueue_message, 'l2Book:eth', { 'seq' => i }) }
      expect(client.dropped_message_count).to eq(0)

      expect { client.send(:enqueue_message, 'l2Book:eth', { 'seq' => 1024 }) }
        .to output(/Queue full \(1024\)/).to_stderr
      expect(client.dropped_message_count).to eq(1)
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

    it 'passes through fast parameter for l2Book subscription' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      expected_msg = JSON.generate({ method: 'subscribe', subscription: { type: 'l2Book', coin: 'ETH', fast: true } })
      expect(mock_ws).to receive(:send).with(expected_msg)

      client.subscribe({ type: 'l2Book', coin: 'ETH', fast: true }, &noop)
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

      wait_until { received.size == 3 }

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

      wait_until { received1.any? && received2.any? }

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

      wait_until { received.any? }

      expect(received).to eq([{ 'ok' => true }])

      client.instance_variable_get(:@queue).close
      client.instance_variable_get(:@dispatch_thread)&.join(1)
    end
  end

  describe 'ping' do
    it 'ping thread sends ping periodically' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      stub_const('Hyperliquid::Constants::WS_PING_INTERVAL', 0.01)
      sent = Queue.new
      allow(mock_ws).to receive(:send) { |frame| sent << frame }

      client.send(:start_ping_thread)

      expect([sent.pop(timeout: 2), sent.pop(timeout: 2)]).to eq(['{"method":"ping"}'] * 2)
    end
  end

  describe 'lifecycle' do
    it 'close stops threads and disconnects' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)

      client.send(:start_dispatch_thread)
      client.send(:start_ping_thread)
      threads = [client.instance_variable_get(:@dispatch_thread), client.instance_variable_get(:@ping_thread)]

      expect(mock_ws).to receive(:close)

      client.close

      expect(client).not_to be_connected
      expect(client.instance_variable_get(:@ws)).to be_nil
      expect(threads.map { |t| t.join(2) && t.alive? }).to eq([false, false])
    end

    it 'on registers lifecycle callbacks' do
      opened = false
      client.on(:open) { opened = true }

      client.send(:handle_open, mock_ws)
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

  describe 'userEvents routing' do
    it 'routes the server channel "user" to the userEvents identifier' do
      expect(client.send(:compute_identifier, 'user', { 'fills' => [] })).to eq('userEvents')
    end

    it 'keys userEvents subscriptions without the user' do
      expect(client.send(:subscription_identifier, { type: 'userEvents', user: '0xABC' })).to eq('userEvents')
    end

    it 'queues "user" channel frames under the subscribed identifier' do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      client.subscribe({ type: 'userEvents', user: '0xABC' }, &noop)
      client.send(:handle_message, { 'channel' => 'user', 'data' => { 'fills' => [] } }.to_json)

      queued = client.instance_variable_get(:@queue).pop(true)
      expect(queued[:identifier]).to eq('userEvents')
      expect(client.instance_variable_get(:@subscriptions).keys).to eq([queued[:identifier]])
    end
  end

  describe 'exclusive subscriptions' do
    before do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
    end

    it 'rejects orderUpdates for a second user without registering it' do
      client.subscribe({ type: 'orderUpdates', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'orderUpdates', user: '0xBBB' }, &noop) }
        .to raise_error(Hyperliquid::WebSocketError, /orderUpdates messages do not include user/)
      expect(client.instance_variable_get(:@subscription_msgs).size).to eq(1)
    end

    it 'allows orderUpdates for the same user regardless of case' do
      client.subscribe({ type: 'orderUpdates', user: '0xaaa' }, &noop)
      client.subscribe({ type: 'orderUpdates', user: '0xAAA' }, &noop)

      expect(client.instance_variable_get(:@subscriptions)['orderUpdates'].size).to eq(2)
    end

    it 'rejects userEvents for a second user' do
      client.subscribe({ type: 'userEvents', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'userEvents', user: '0xBBB' }, &noop) }
        .to raise_error(Hyperliquid::WebSocketError, /userEvents messages do not include user/)
    end

    it 'frees the channel for another user after unsubscribe' do
      id = client.subscribe({ type: 'orderUpdates', user: '0xAAA' }, &noop)
      client.unsubscribe(id)

      expect { client.subscribe({ type: 'orderUpdates', user: '0xBBB' }, &noop) }.not_to raise_error
    end

    it 'allows a non-exclusive channel for two users' do
      client.subscribe({ type: 'userFills', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'userFills', user: '0xBBB' }, &noop) }.not_to raise_error
    end

    it 'rejects userFills for the same user with a different aggregateByTime' do
      client.subscribe({ type: 'userFills', user: '0xAAA', aggregateByTime: true }, &noop)

      expect { client.subscribe({ type: 'userFills', user: '0xAAA' }, &noop) }
        .to raise_error(Hyperliquid::WebSocketError, /aggregateByTime/)
    end

    it 'treats an omitted aggregateByTime as false' do
      client.subscribe({ type: 'userFills', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'userFills', user: '0xAAA', aggregateByTime: false }, &noop) }
        .not_to raise_error
    end

    it 'allows different aggregateByTime settings for different users' do
      client.subscribe({ type: 'userFills', user: '0xAAA', aggregateByTime: true }, &noop)

      expect { client.subscribe({ type: 'userFills', user: '0xBBB', aggregateByTime: false }, &noop) }
        .not_to raise_error
    end

    it 'rejects notification for a second user' do
      client.subscribe({ type: 'notification', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'notification', user: '0xBBB' }, &noop) }
        .to raise_error(Hyperliquid::WebSocketError, /notification messages do not include user/)
    end

    it 'rejects spotState for the same user with a different ignorePortfolioMargin' do
      client.subscribe({ type: 'spotState', user: '0xAAA', ignorePortfolioMargin: true }, &noop)

      expect { client.subscribe({ type: 'spotState', user: '0xAAA' }, &noop) }
        .to raise_error(Hyperliquid::WebSocketError, /ignorePortfolioMargin/)
    end

    it 'treats an omitted ignorePortfolioMargin as false' do
      client.subscribe({ type: 'spotState', user: '0xAAA' }, &noop)

      expect { client.subscribe({ type: 'spotState', user: '0xAAA', ignorePortfolioMargin: false }, &noop) }
        .not_to raise_error
    end

    it 'allows different ignorePortfolioMargin settings for different users' do
      client.subscribe({ type: 'spotState', user: '0xAAA', ignorePortfolioMargin: true }, &noop)

      expect { client.subscribe({ type: 'spotState', user: '0xBBB', ignorePortfolioMargin: false }, &noop) }
        .not_to raise_error
    end
  end

  describe 'parity channel routing' do
    upper = '0x4EF66DF2067C588EB98896EDE3A8E80F85AFF085'
    user = upper.downcase

    # [label, subscription, server channel, message data, expected identifier]
    [
      [
        'userNonFundingLedgerUpdates',
        { type: 'userNonFundingLedgerUpdates', user: upper },
        'userNonFundingLedgerUpdates',
        { 'isSnapshot' => true, 'user' => user, 'nonFundingLedgerUpdates' => [] },
        "userNonFundingLedgerUpdates:#{user}"
      ],
      [
        'userTwapSliceFills',
        { type: 'userTwapSliceFills', user: upper },
        'userTwapSliceFills',
        { 'user' => user, 'twapSliceFills' => [] },
        "userTwapSliceFills:#{user}"
      ],
      [
        'userTwapHistory',
        { type: 'userTwapHistory', user: upper },
        'userTwapHistory',
        { 'user' => user, 'history' => [] },
        "userTwapHistory:#{user}"
      ],
      [
        'userHistoricalOrders',
        { type: 'userHistoricalOrders', user: upper },
        'userHistoricalOrders',
        { 'user' => user, 'orderHistory' => [] },
        "userHistoricalOrders:#{user}"
      ],
      [
        'allDexsClearinghouseState',
        { type: 'allDexsClearinghouseState', user: upper },
        'allDexsClearinghouseState',
        { 'user' => user, 'clearinghouseStates' => [] },
        "allDexsClearinghouseState:#{user}"
      ],
      [
        'webData3',
        { type: 'webData3', user: upper },
        'webData3',
        { 'userState' => { 'user' => user }, 'perpDexStates' => [] },
        "webData3:#{user}"
      ],
      [
        'clearinghouseState (no dex)',
        { type: 'clearinghouseState', user: upper },
        'clearinghouseState',
        { 'dex' => '', 'user' => user, 'clearinghouseState' => {} },
        "clearinghouseState:#{user}:"
      ],
      [
        'clearinghouseState (dex xyz)',
        { type: 'clearinghouseState', user: upper, dex: 'xyz' },
        'clearinghouseState',
        { 'dex' => 'xyz', 'user' => user, 'clearinghouseState' => {} },
        "clearinghouseState:#{user}:xyz"
      ],
      [
        'openOrders (dex xyz)',
        { type: 'openOrders', user: upper, dex: 'xyz' },
        'openOrders',
        { 'dex' => 'xyz', 'user' => user, 'orders' => [] },
        "openOrders:#{user}:xyz"
      ],
      [
        'twapStates (no dex)',
        { type: 'twapStates', user: upper },
        'twapStates',
        { 'dex' => '', 'user' => user, 'states' => [] },
        "twapStates:#{user}:"
      ],
      [
        'spotState',
        { type: 'spotState', user: upper, ignorePortfolioMargin: true },
        'spotState',
        { 'user' => user, 'spotState' => { 'balances' => [] } },
        "spotState:#{user}"
      ],
      [
        'notification',
        { type: 'notification', user: upper },
        'notification',
        { 'notification' => 'x' },
        'notification'
      ],
      [
        'activeAssetCtx (perp)',
        { type: 'activeAssetCtx', coin: 'BTC' },
        'activeAssetCtx',
        { 'coin' => 'BTC', 'ctx' => {} },
        'activeAssetCtx:btc'
      ],
      [
        'activeAssetCtx (HIP-3)',
        { type: 'activeAssetCtx', coin: 'xyz:XYZ100' },
        'activeAssetCtx',
        { 'coin' => 'xyz:XYZ100', 'ctx' => {} },
        'activeAssetCtx:xyz:xyz100'
      ],
      [
        'activeAssetCtx (spot, echoed as activeSpotAssetCtx)',
        { type: 'activeAssetCtx', coin: 'PURR/USDC' },
        'activeSpotAssetCtx',
        { 'coin' => 'PURR/USDC', 'ctx' => {} },
        'activeAssetCtx:purr/usdc'
      ],
      [
        'activeAssetData',
        { type: 'activeAssetData', user: upper, coin: 'BTC' },
        'activeAssetData',
        { 'user' => user, 'coin' => 'BTC', 'leverage' => {} },
        "activeAssetData:#{user}:btc"
      ],
      [
        'assetCtxs (no dex)',
        { type: 'assetCtxs' },
        'assetCtxs',
        { 'dex' => '', 'ctxs' => [] },
        'assetCtxs:'
      ],
      [
        'assetCtxs (dex xyz)',
        { type: 'assetCtxs', dex: 'xyz' },
        'assetCtxs',
        { 'dex' => 'xyz', 'ctxs' => [] },
        'assetCtxs:xyz'
      ],
      [
        'allDexsAssetCtxs',
        { type: 'allDexsAssetCtxs' },
        'allDexsAssetCtxs',
        { 'ctxs' => [] },
        'allDexsAssetCtxs'
      ],
      [
        'spotAssetCtxs (Array payload)',
        { type: 'spotAssetCtxs' },
        'spotAssetCtxs',
        [{ 'coin' => 'PURR/USDC' }],
        'spotAssetCtxs'
      ],
      [
        'outcomeMetaUpdates',
        { type: 'outcomeMetaUpdates' },
        'outcomeMetaUpdates',
        { 'updates' => [] },
        'outcomeMetaUpdates'
      ]
    ].each do |label, subscription, channel, data, expected|
      it "routes #{label} subscriptions and messages to #{expected}" do
        expect(client.send(:subscription_identifier, subscription)).to eq(expected)
        expect(client.send(:compute_identifier, channel, data)).to eq(expected)
      end
    end

    it 'does not accept activeSpotAssetCtx as a subscription type' do
      expect { client.send(:subscription_identifier, { type: 'activeSpotAssetCtx', coin: '@107' }) }
        .to raise_error(Hyperliquid::WebSocketError, /Unsupported subscription type/)
    end

    it 'keeps a dex subscription apart from main-dex messages' do
      expect(client.send(:subscription_identifier, { type: 'clearinghouseState', user: upper, dex: 'xyz' }))
        .not_to eq(client.send(:compute_identifier, 'clearinghouseState', { 'dex' => '', 'user' => user }))
    end

    it 'treats an omitted dex and dex: "" as the same subscription' do
      expect(client.send(:subscription_identifier, { type: 'clearinghouseState', user: upper, dex: '' }))
        .to eq(client.send(:subscription_identifier, { type: 'clearinghouseState', user: upper }))
    end

    it 'keeps openOrders for two users apart' do
      expect(client.send(:subscription_identifier, { type: 'openOrders', user: '0xAAA' }))
        .not_to eq(client.send(:subscription_identifier, { type: 'openOrders', user: '0xBBB' }))
    end

    it 'keeps activeAssetData for one user on two coins apart' do
      expect(client.send(:subscription_identifier, { type: 'activeAssetData', user: upper, coin: 'BTC' }))
        .not_to eq(client.send(:subscription_identifier, { type: 'activeAssetData', user: upper, coin: 'ETH' }))
    end
  end

  describe 'fastAssetCtxs (base64 + raw DEFLATE channel)' do
    let(:queue) { client.instance_variable_get(:@queue) }
    # Official example from the GitBook WS subscriptions page (fastAssetCtxs, "Example to test your implementation").
    let(:docs_payload) { 'q1ZyCnFWsqpWyk0syg6oULJSsjQ3NTDQM1Wq1VFyDfFAkTI2MzXQMwJLVVRWWfmFuTiiyBuamOoZKdXWAgA=' }
    let(:docs_decoded) do
      { 'BTC' => { 'markPx' => '97500.5' }, 'ETH' => { 'markPx' => '3650.25' }, 'xyz:NVDA' => { 'markPx' => '145.2' } }
    end

    def raw_deflate_base64(json)
      deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
      compressed = deflater.deflate(json, Zlib::FINISH)
      deflater.close
      [compressed].pack('m0')
    end

    def frame(data)
      { 'channel' => 'fastAssetCtxs', 'data' => data }.to_json
    end

    before do
      client.instance_variable_set(:@connected, true)
      client.instance_variable_set(:@ws, mock_ws)
      client.subscribe({ type: 'fastAssetCtxs' }) { |_d| }
    end

    it 'uses a parameterless identifier for subscribe and for incoming frames' do
      expect(client.send(:subscription_identifier, { type: 'fastAssetCtxs' })).to eq('fastAssetCtxs')
      expect(client.send(:subscription_identifier, { 'type' => 'fastAssetCtxs' })).to eq('fastAssetCtxs')
      expect(client.send(:compute_identifier, 'fastAssetCtxs', {})).to eq('fastAssetCtxs')
    end

    it 'sends the subscription verbatim' do
      expect(mock_ws).to have_received(:send)
        .with('{"method":"subscribe","subscription":{"type":"fastAssetCtxs"}}')
    end

    it 'decodes the documented example payload into a coin-keyed Hash' do
      client.send(:handle_message, frame(docs_payload))

      queued = queue.pop(true)
      expect(queued[:identifier]).to eq('fastAssetCtxs')
      expect(queued[:data]).to eq(docs_decoded)
    end

    it 'decodes a real captured testnet update frame, preserving omitted fields' do
      raw = File.read(File.expand_path('../../fixtures/ws/fast_asset_ctxs_update.json', __dir__))
      client.send(:handle_message, raw)

      data = queue.pop(true)[:data]
      expect(data.size).to eq(65)
      expect(data['AAVE']).to eq({ 'midPx' => '167.87' })
      expect(data['bart:BTC']).to eq({ 'markPx' => '88297.0' })
      expect(data['CHIP']).to eq({ 'midPx' => '0.041527' })
      expect(data.values).to all(satisfy { |ctx| !ctx.empty? && (ctx.keys - %w[markPx midPx]).empty? })
    end

    it 'keeps a null midPx as nil and decodes UTF-8 keys' do
      client.send(:handle_message, frame(raw_deflate_base64('{"BTC":{"markPx":"1","midPx":null},"€X":{"midPx":"2"}}')))

      data = queue.pop(true)[:data]
      expect(data).to eq({ 'BTC' => { 'markPx' => '1', 'midPx' => nil }, '€X' => { 'midPx' => '2' } })
      expect(data.keys.last.encoding).to eq(Encoding::UTF_8)
    end

    it 'drops and warns on invalid base64 without raising' do
      expect { client.send(:handle_message, frame('not base64!')) }
        .to output(/Failed to decode compressed message: ArgumentError/).to_stderr
      expect(queue).to be_empty
    end

    it 'rejects zlib-wrapped (RFC 1950) data: the channel is raw DEFLATE only' do
      wrapped = [Zlib::Deflate.deflate('{"BTC":{"markPx":"1"}}')].pack('m0')
      expect { client.send(:handle_message, frame(wrapped)) }
        .to output(/Failed to decode compressed message: Zlib::DataError/).to_stderr
      expect(queue).to be_empty
    end

    it 'drops and warns on a truncated DEFLATE stream' do
      truncated = [docs_payload.unpack1('m0')[0, 20]].pack('m0')
      expect { client.send(:handle_message, frame(truncated)) }
        .to output(/Failed to decode compressed message: Zlib::BufError: truncated DEFLATE stream/).to_stderr
      expect(queue).to be_empty
    end

    it 'drops and warns when the inflated bytes are not JSON' do
      expect { client.send(:handle_message, frame(raw_deflate_base64('not json'))) }
        .to output(/Failed to decode compressed message: JSON::ParserError/).to_stderr
      expect(queue).to be_empty
    end

    it 'drops and warns when data is not a String' do
      expect { client.send(:handle_message, { 'channel' => 'fastAssetCtxs', 'data' => { 'BTC' => {} } }.to_json) }
        .to output(/Failed to decode compressed message: expected String, got Hash/).to_stderr
      expect(queue).to be_empty
    end

    it 'keeps processing frames after a bad one' do
      expect { client.send(:handle_message, frame('%%%')) }.to output.to_stderr
      client.send(:handle_message, frame(docs_payload))

      expect(queue.pop(true)[:data]).to eq(docs_decoded)
    end

    it 'delivers the decoded Hash to callbacks on the dispatch thread' do
      received = []
      client.subscribe({ type: 'fastAssetCtxs' }) { |d| received << d }
      client.send(:start_dispatch_thread)

      client.send(:handle_message, frame(docs_payload))
      wait_until { received.any? }

      expect(received).to eq([docs_decoded])
      queue.close
      client.instance_variable_get(:@dispatch_thread)&.join(1)
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
      ws = instance_double(WSLite::Client)
      allow(ws).to receive(:send)
      allow(ws).to receive(:close)
      allow(ws).to receive(:on)
      ws
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
          { 'channel' => 'user', 'data' => { 'fills' => [] } },
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
        expect(explorer_client.send(:compute_identifier, 'user', { 'fills' => [] })).to eq('userEvents')
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

      it 'subscription IDs are unique across main-API and explorer subscriptions' do
        main_id = explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
        explorer_id = explorer_client.subscribe_explorer_block { |_d| }

        expect(explorer_id).not_to eq(main_id)
      end

      it 'unsubscribing an explorer ID leaves main-API subscriptions intact' do
        explorer_client.instance_variable_set(:@connected, true)
        explorer_client.instance_variable_set(:@ws, mock_ws)
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_ws).to receive(:send)
        allow(mock_explorer_ws).to receive(:send)

        explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
        explorer_id = explorer_client.subscribe_explorer_block { |_d| }
        explorer_client.unsubscribe(explorer_id)

        expect(explorer_client.instance_variable_get(:@subscriptions)).to have_key('l2Book:eth')
        expect(explorer_client.instance_variable_get(:@explorer_subscriptions)).not_to have_key('explorerBlock')
        unsub_block = JSON.generate({ method: 'unsubscribe', subscription: { type: 'explorerBlock' } })
        expect(mock_explorer_ws).to have_received(:send).with(unsub_block)
        expect(mock_ws).not_to have_received(:send).with(/"method":"unsubscribe"/)
      end

      it 'unsubscribing a main-API ID leaves explorer subscriptions intact' do
        explorer_client.instance_variable_set(:@connected, true)
        explorer_client.instance_variable_set(:@ws, mock_ws)
        explorer_client.instance_variable_set(:@explorer_connected, true)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)
        allow(mock_ws).to receive(:send)
        allow(mock_explorer_ws).to receive(:send)

        explorer_client.subscribe_explorer_block { |_d| }
        main_id = explorer_client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
        explorer_client.unsubscribe(main_id)

        expect(explorer_client.instance_variable_get(:@explorer_subscriptions)).to have_key('explorerBlock')
        expect(explorer_client.instance_variable_get(:@subscriptions)).not_to have_key('l2Book:eth')
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

        wait_until { received.size == 3 }

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

        wait_until { received.any? }

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

        wait_until { received1.any? && received2.any? }

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
        stub_const('Hyperliquid::Constants::WS_PING_INTERVAL', 0.01)
        sent = Queue.new
        allow(mock_explorer_ws).to receive(:send) { |frame| sent << frame }

        explorer_client.send(:start_explorer_ping_thread)

        expect([sent.pop(timeout: 2), sent.pop(timeout: 2)]).to eq(['{"method":"ping"}'] * 2)
      end
    end

    describe 'explorer lifecycle' do
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

      it 'close stops both ping threads and both dispatch threads' do
        explorer_client.instance_variable_set(:@ws, mock_ws)
        explorer_client.instance_variable_set(:@explorer_ws, mock_explorer_ws)

        explorer_client.send(:start_dispatch_thread)
        explorer_client.send(:start_ping_thread)
        explorer_client.send(:start_explorer_dispatch_thread)
        explorer_client.send(:start_explorer_ping_thread)
        threads = %i[@dispatch_thread @ping_thread @explorer_dispatch_thread @explorer_ping_thread]
                  .map { |ivar| explorer_client.instance_variable_get(ivar) }

        explorer_client.close

        expect(threads.map { |t| t.join(2) && t.alive? }).to eq([false] * 4)
      end
    end
  end

  # ── Socket lifecycle, driven through a fake ws_lite socket ──────

  describe 'socket lifecycle' do
    let(:sockets) { [] }
    let(:backoff_delays) { [] }
    let(:backoff_gate) { Queue.new }
    let(:eth_book) { { 'type' => 'l2Book', 'coin' => 'ETH' } }
    let(:eth_frame) { { channel: 'l2Book', data: { coin: 'ETH', levels: [] } }.to_json }

    def subscribe_frame(subscription)
      { 'method' => 'subscribe', 'subscription' => subscription }
    end

    # Backoff sleeps are recorded and return at once (or block on `gate`); the ping sleep stays real.
    def stub_backoff(target, gate: nil)
      allow(target).to receive(:sleep).and_wrap_original do |original, seconds|
        next original.call(seconds) if seconds == Hyperliquid::Constants::WS_PING_INTERVAL

        backoff_delays << seconds
        gate&.pop
      end
    end

    def capture_reconnect_threads(target, method_name)
      threads = []
      allow(target).to receive(method_name).and_wrap_original do |original|
        original.call.tap { |thread| threads << thread }
      end
      threads
    end

    before do
      @refusals = 0
      allow(WSLite).to receive(:connect) do |url, &block|
        if @refusals.positive?
          @refusals -= 1
          raise Errno::ECONNREFUSED
        end

        FakeWSLiteSocket.new(url).tap do |socket|
          block.call(socket)
          sockets << socket
        end
      end
    end

    after { backoff_gate.close }

    it 'connects to the mainnet and testnet API WebSocket URLs' do
      client.connect
      testnet_client.connect

      expect(sockets.map(&:url)).to eq(%w[wss://api.hyperliquid.xyz/ws wss://api.hyperliquid-testnet.xyz/ws])
    end

    it 'connects the SDK explorer streams to the per-network RPC WebSocket URLs' do
      Hyperliquid.new.ws.subscribe_explorer_block(&noop)
      Hyperliquid.new(testnet: true).ws.subscribe_explorer_txs(&noop)

      expect(sockets.map(&:url)).to eq(%w[wss://rpc.hyperliquid.xyz/ws wss://rpc.hyperliquid-testnet.xyz/ws])
    end

    it 'sends each live subscription exactly once when the socket opens' do
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
      trades_id = client.subscribe({ type: 'trades', coin: 'BTC' }, &noop)
      client.subscribe({ type: 'allMids' }, &noop)
      client.unsubscribe(trades_id)
      expect(sockets.size).to eq(1)
      expect(sockets[0].sent).to be_empty

      sockets[0].emit(:open)

      expect(sockets[0].sent_json).to eq([subscribe_frame(eth_book), subscribe_frame({ 'type' => 'allMids' })])
      expect(client).to be_connected
    end

    it 'reconnects after a drop and replays subscriptions on the new socket' do
      stub_backoff(client)
      received = Queue.new
      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }
      sockets[0].emit(:open)

      sockets[0].drop!
      expect(client).not_to be_connected
      wait_until { sockets.size == 2 }
      sockets[1].emit(:open)

      expect(client).to be_connected
      expect(sockets[1].sent_json).to eq([subscribe_frame(eth_book)])
      sockets[1].receive(eth_frame)
      expect(received.pop(timeout: 2)).to eq({ 'coin' => 'ETH', 'levels' => [] })
    end

    it 'backs off 1, 2, 4, 8, 16, then 30 s while reconnects fail, and resets after an open' do
      stub_backoff(client)
      client.connect
      sockets[0].emit(:open)
      @refusals = 7

      expect do
        sockets[0].drop!
        wait_until { sockets.size == 2 }
      end.to output(/\A(?:\[Hyperliquid::WS\] Reconnect failed: Connection refused\n){7}\z/).to_stderr
      expect(backoff_delays).to eq([1, 2, 4, 8, 16, 30, 30, 30])

      sockets[1].emit(:open)
      backoff_delays.clear
      sockets[1].drop!
      wait_until { sockets.size == 3 }
      expect(backoff_delays).to eq([1])
    end

    it 'ignores a late close from a superseded socket' do
      closes = 0
      client.on(:close) { closes += 1 }
      stub_backoff(client)
      client.connect
      sockets[0].emit(:open)
      sockets[0].drop!
      wait_until { sockets.size == 2 }
      sockets[1].emit(:open)

      sockets[0].emit(:close)

      expect(client).to be_connected
      expect(closes).to eq(1)
      expect(sockets.size).to eq(2)
    end

    it 'fires on(:close) once when the client closes the socket' do
      closes = 0
      client.on(:close) { closes += 1 }
      client.connect
      sockets[0].emit(:open)

      client.close

      expect(closes).to eq(1)
      expect(client).not_to be_connected
    end

    it 'stops reconnecting when closed during backoff' do
      stub_backoff(client, gate: backoff_gate)
      threads = capture_reconnect_threads(client, :attempt_reconnect)
      client.connect
      sockets[0].emit(:open)
      sockets[0].drop!
      wait_until { backoff_delays.any? }

      client.close
      backoff_gate << :wake

      expect(threads.fetch(0).join(2)).to be_truthy
      expect(sockets.size).to eq(1)
    end

    it 'does not let a backoff thread from before close open a second socket after connect' do
      stub_backoff(client, gate: backoff_gate)
      threads = capture_reconnect_threads(client, :attempt_reconnect)
      client.connect
      sockets[0].emit(:open)
      sockets[0].drop!
      wait_until { backoff_delays.any? }

      client.close
      client.connect
      backoff_gate << :wake

      expect(threads.fetch(0).join(2)).to be_truthy
      expect(sockets.size).to eq(2)
    end

    it 'delivers messages again after close and a new subscribe' do
      received = Queue.new
      client.subscribe({ type: 'l2Book', coin: 'BTC' }, &noop)
      sockets[0].emit(:open)
      client.close

      client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }
      sockets[1].emit(:open)
      sockets[1].receive(eth_frame)

      expect(sockets[1].sent_json).to include(subscribe_frame(eth_book))
      expect(received.pop(timeout: 2)).to eq({ 'coin' => 'ETH', 'levels' => [] })
    end

    it 'drops a frame that races close without reporting an error' do
      errors = []
      client.on(:error) { |e| errors << e }
      client.subscribe({ type: 'l2Book', coin: 'ETH' }, &noop)
      socket = sockets[0]
      socket.emit(:open)
      # The socket thread reads one more frame after close has shut the queue, before the socket closes.
      allow(socket).to receive(:close).and_wrap_original do |original|
        socket.receive(eth_frame)
        original.call
      end

      client.close

      expect(errors).to eq([])
    end

    describe 'explorer socket' do
      let(:explorer_client) { described_class.new(explorer_ws_url: 'wss://explorer.test/ws') }
      let(:block_sub) { subscribe_frame({ 'type' => 'explorerBlock' }) }
      let(:txs_sub) { subscribe_frame({ 'type' => 'explorerTxs' }) }
      let(:blocks) { [{ 'blockTime' => 1, 'hash' => '0xa', 'height' => 7, 'numTxs' => 0, 'proposer' => '0x1' }] }

      it 'subscribes once on open, and reconnects and replays after a drop' do
        stub_backoff(explorer_client)
        received = Queue.new
        explorer_client.subscribe_explorer_block { |d| received << d }
        explorer_client.subscribe_explorer_txs(&noop)
        sockets[0].emit(:open)
        expect(sockets[0].sent_json).to eq([block_sub, txs_sub])

        sockets[0].drop!
        wait_until { sockets.size == 2 }
        sockets[1].emit(:open)

        expect(backoff_delays).to eq([1])
        expect(explorer_client).to be_explorer_connected
        expect(sockets[1].sent_json).to eq([block_sub, txs_sub])
        sockets[1].receive(blocks.to_json)
        expect(received.pop(timeout: 2)).to eq(blocks)
      end

      it 'cancels backoff on close, and a later subscribe gets a working socket' do
        stub_backoff(explorer_client, gate: backoff_gate)
        threads = capture_reconnect_threads(explorer_client, :attempt_explorer_reconnect)
        explorer_client.subscribe_explorer_block(&noop)
        sockets[0].emit(:open)
        sockets[0].drop!
        wait_until { backoff_delays.any? }

        explorer_client.close
        received = Queue.new
        explorer_client.subscribe_explorer_txs { |d| received << d }
        backoff_gate << :wake

        expect(threads.fetch(0).join(2)).to be_truthy
        expect(sockets.size).to eq(2)
        sockets[1].emit(:open)
        txs = [{ 'action' => {}, 'block' => 1, 'error' => nil, 'hash' => '0xb', 'time' => 1, 'user' => '0x2' }]
        sockets[1].receive(txs.to_json)
        expect(received.pop(timeout: 2)).to eq(txs)
      end
    end
  end
end
