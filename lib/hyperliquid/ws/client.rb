# frozen_string_literal: true

require 'ws_lite'
require 'json'

module Hyperliquid
  module WS
    # Managed WebSocket client for subscribing to real-time data channels
    class Client
      attr_reader :dropped_message_count, :explorer_dropped_message_count

      def initialize(testnet: false, max_queue_size: Constants::WS_MAX_QUEUE_SIZE, reconnect: true,
                     explorer_ws_url: nil)
        base_url = testnet ? Constants::TESTNET_API_URL : Constants::MAINNET_API_URL
        @url = base_url.sub(%r{^https?://}, 'wss://') + Constants::WS_ENDPOINT
        @max_queue_size = max_queue_size
        @reconnect_enabled = reconnect
        @mutex = Mutex.new

        init_main_ws_state
        init_explorer_ws_state(explorer_ws_url)
      end

      private

      def init_main_ws_state
        @subscriptions = {}      # identifier => [{ id:, callback: }]
        @subscription_msgs = {}  # subscription_id => { subscription:, identifier: }
        @next_id = 0
        @queue = Queue.new
        @dropped_message_count = 0
        @ws = nil
        @connected = false
        @closing = false
        @dispatch_thread = nil
        @ping_thread = nil
        @pending_subscriptions = []
        @lifecycle_callbacks = {}
        @reconnect_attempts = 0
        @connection_id = 0
      end

      def init_explorer_ws_state(explorer_ws_url)
        @explorer_ws_url = explorer_ws_url
        @explorer_ws = nil
        @explorer_connected = false
        @explorer_closing = false
        @explorer_connection_id = 0
        @explorer_reconnect_attempts = 0
        @explorer_subscriptions = {}
        @explorer_subscription_msgs = {}
        @explorer_next_id = 0
        @explorer_queue = Queue.new
        @explorer_dropped_message_count = 0
        @explorer_dispatch_thread = nil
        @explorer_ping_thread = nil
        @explorer_pending_subscriptions = []
      end

      public

      def connect
        @closing = false
        @reconnect_attempts = 0
        establish_connection
        start_dispatch_thread
        start_ping_thread
        self
      end

      def subscribe(subscription, &callback)
        raise ArgumentError, 'Block required for subscribe' unless block_given?

        identifier = subscription_identifier(subscription)
        sub_id = nil

        @mutex.synchronize do
          sub_id = @next_id
          @next_id += 1

          @subscriptions[identifier] ||= []
          @subscriptions[identifier] << { id: sub_id, callback: callback }
          @subscription_msgs[sub_id] = { subscription: subscription, identifier: identifier }
        end

        if @connected
          send_subscribe(subscription)
        else
          @mutex.synchronize { @pending_subscriptions << subscription }
          connect unless @ws
        end

        sub_id
      end

      def subscribe_explorer_block(&)
        raise ArgumentError, 'Block required for subscribe_explorer_block' unless block_given?
        raise ConfigurationError, 'Explorer WebSocket URL not configured' unless @explorer_ws_url

        subscribe_explorer({ type: 'explorerBlock' }, 'explorerBlock', &)
      end

      def subscribe_explorer_txs(&)
        raise ArgumentError, 'Block required for subscribe_explorer_txs' unless block_given?
        raise ConfigurationError, 'Explorer WebSocket URL not configured' unless @explorer_ws_url

        subscribe_explorer({ type: 'explorerTxs' }, 'explorerTxs', &)
      end

      def unsubscribe(subscription_id)
        sub_msg = nil
        should_send = false
        explorer = false

        @mutex.synchronize do
          sub_msg = @subscription_msgs.delete(subscription_id)
          unless sub_msg
            sub_msg = @explorer_subscription_msgs.delete(subscription_id)
            explorer = true if sub_msg
          end
          return unless sub_msg

          identifier = sub_msg[:identifier]
          map = explorer ? @explorer_subscriptions : @subscriptions
          callbacks = map[identifier]
          return unless callbacks

          callbacks.reject! { |entry| entry[:id] == subscription_id }

          if callbacks.empty?
            map.delete(identifier)
            should_send = true
          end
        end

        return unless should_send

        if explorer
          send_explorer_unsubscribe(sub_msg[:subscription]) if @explorer_connected
        elsif @connected
          send_unsubscribe(sub_msg[:subscription])
        end
      end

      def close
        @closing = true
        @connected = false
        @explorer_closing = true
        @explorer_connected = false

        @ping_thread&.kill
        @ping_thread = nil
        @explorer_ping_thread&.kill
        @explorer_ping_thread = nil

        @queue&.close if @queue.respond_to?(:close)
        @explorer_queue&.close if @explorer_queue.respond_to?(:close)

        @dispatch_thread&.join(5)
        @dispatch_thread = nil
        @explorer_dispatch_thread&.join(5)
        @explorer_dispatch_thread = nil

        @ws&.close
        @ws = nil
        @explorer_ws&.close
        @explorer_ws = nil
      end

      def connected?
        @connected
      end

      def explorer_connected?
        @explorer_connected
      end

      def on(event, &callback)
        @lifecycle_callbacks[event] = callback
      end

      private

      def establish_connection
        client = self
        url = @url
        @connection_id += 1
        active_id = @connection_id

        @ws = ::WSLite.connect(url) do |ws|
          ws.on :open do
            next if client.send(:stale_connection?, active_id)

            client.send(:handle_open)
          end

          ws.on :message do |msg|
            next if client.send(:stale_connection?, active_id)

            client.send(:handle_message, msg.data)
          end

          ws.on :error do |e|
            next if client.send(:stale_connection?, active_id)

            client.send(:handle_error, e)
          end

          ws.on :close do |e|
            next if client.send(:stale_connection?, active_id)

            client.send(:handle_close, e)
          end
        end
      end

      def stale_connection?(id)
        id != @connection_id
      end

      def handle_open
        @connected = true
        @reconnect_attempts = 0
        flush_pending_subscriptions
        replay_subscriptions
        @lifecycle_callbacks[:open]&.call
      end

      def handle_message(raw)
        return if raw.nil? || raw.empty?

        return if raw.start_with?('Websocket connection established')

        data = parse_json(raw)
        return unless data

        channel = data['channel']
        return if channel == 'pong'
        return unless channel

        identifier = compute_identifier(channel, data['data'])
        return unless identifier

        enqueue_message(identifier, data['data'])
      end

      def handle_error(error)
        @lifecycle_callbacks[:error]&.call(error)
      end

      def handle_close(_event)
        was_connected = @connected
        @connected = false
        @lifecycle_callbacks[:close]&.call

        attempt_reconnect if was_connected && !@closing && @reconnect_enabled
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError => e
        warn "[Hyperliquid::WS] Failed to parse message: #{e.message}"
        nil
      end

      def compute_identifier(channel, data)
        case channel
        when 'l2Book'        then "l2Book:#{data['coin'].downcase}"
        when 'trades'        then data.is_a?(Array) && data[0] ? "trades:#{data[0]['coin'].downcase}" : nil
        when 'bbo'           then "bbo:#{data['coin'].downcase}"
        when 'candle'        then "candle:#{data['s'].downcase}:#{data['i']}"
        when 'allMids'       then 'allMids'
        when 'orderUpdates'  then 'orderUpdates'
        when 'userEvents'    then "userEvents:#{data['user'].downcase}"
        when 'userFills'     then "userFills:#{data['user'].downcase}"
        when 'userFundings'  then "userFundings:#{data['user'].downcase}"
        end
      end

      def subscription_identifier(subscription)
        type = sub_field(subscription, 'type')
        case type
        when 'l2Book'        then "l2Book:#{sub_field(subscription, 'coin').downcase}"
        when 'trades'        then "trades:#{sub_field(subscription, 'coin').downcase}"
        when 'bbo'           then "bbo:#{sub_field(subscription, 'coin').downcase}"
        when 'candle'
          "candle:#{sub_field(subscription, 'coin').downcase}:#{sub_field(subscription, 'interval')}"
        when 'allMids'       then 'allMids'
        when 'orderUpdates'  then 'orderUpdates'
        when 'userEvents'    then "userEvents:#{sub_field(subscription, 'user').downcase}"
        when 'userFills'     then "userFills:#{sub_field(subscription, 'user').downcase}"
        when 'userFundings'  then "userFundings:#{sub_field(subscription, 'user').downcase}"
        else
          raise Hyperliquid::WebSocketError, "Unsupported subscription type: #{type}"
        end
      end

      def sub_field(subscription, key)
        subscription[key.to_sym] || subscription[key]
      end

      def enqueue_message(identifier, data)
        @mutex.synchronize do
          if @queue.size >= @max_queue_size
            @dropped_message_count += 1
            if @dropped_message_count == 1 || (@dropped_message_count % 100).zero?
              warn "[Hyperliquid::WS] Queue full (#{@max_queue_size}). " \
                   "Dropped #{@dropped_message_count} message(s). Callbacks may be too slow."
            end
            return
          end
        end
        @queue.push({ identifier: identifier, data: data })
      end

      def start_dispatch_thread
        @dispatch_thread = Thread.new do
          loop do
            msg = begin
              @queue.pop
            rescue ClosedQueueError
              break
            end
            break if msg.nil?

            callbacks = @mutex.synchronize { @subscriptions[msg[:identifier]]&.dup }
            next unless callbacks

            callbacks.each do |entry|
              entry[:callback].call(msg[:data])
            rescue StandardError => e
              warn "[Hyperliquid::WS] Callback error: #{e.message}"
            end
          end
        end
        @dispatch_thread.name = 'hl-ws-dispatch'
      end

      def start_ping_thread
        @ping_thread = Thread.new do
          loop do
            sleep Constants::WS_PING_INTERVAL
            break if @closing

            send_json({ method: 'ping' }) if @connected
          end
        end
        @ping_thread.name = 'hl-ws-ping'
        @ping_thread.report_on_exception = false
      end

      def flush_pending_subscriptions
        pending = @mutex.synchronize do
          subs = @pending_subscriptions.dup
          @pending_subscriptions.clear
          subs
        end

        pending.each { |sub| send_subscribe(sub) }
      end

      def send_subscribe(subscription)
        send_json({ method: 'subscribe', subscription: subscription })
      end

      def send_unsubscribe(subscription)
        send_json({ method: 'unsubscribe', subscription: subscription })
      end

      def send_json(hash)
        @ws&.send(JSON.generate(hash))
      rescue StandardError => e
        warn "[Hyperliquid::WS] Send error: #{e.message}"
      end

      def attempt_reconnect
        Thread.new do
          loop do
            break if @closing

            delay = [2**@reconnect_attempts, 30].min
            @reconnect_attempts += 1
            sleep delay

            break if @closing

            begin
              establish_connection
              break
            rescue StandardError => e
              warn "[Hyperliquid::WS] Reconnect failed: #{e.message}"
            end
          end
        end
      end

      def replay_subscriptions
        subs = @mutex.synchronize do
          @subscription_msgs.values.map { |v| v[:subscription] }.uniq
        end
        subs.each { |sub| send_subscribe(sub) }
      end

      # ── Explorer WebSocket ──────────────────────────────────────────

      def subscribe_explorer(subscription, identifier, &callback)
        sub_id = nil

        @mutex.synchronize do
          sub_id = @explorer_next_id
          @explorer_next_id += 1

          @explorer_subscriptions[identifier] ||= []
          @explorer_subscriptions[identifier] << { id: sub_id, callback: callback }
          @explorer_subscription_msgs[sub_id] = { subscription: subscription, identifier: identifier }
        end

        if @explorer_connected
          send_explorer_subscribe(subscription)
        else
          @mutex.synchronize { @explorer_pending_subscriptions << subscription }
          establish_explorer_connection unless @explorer_ws
          start_explorer_dispatch_thread unless @explorer_dispatch_thread
          start_explorer_ping_thread unless @explorer_ping_thread
        end

        sub_id
      end

      def establish_explorer_connection
        client = self
        url = @explorer_ws_url
        @explorer_connection_id += 1
        active_id = @explorer_connection_id

        @explorer_ws = ::WSLite.connect(url) do |ws|
          ws.on :open do
            next if client.send(:stale_explorer_connection?, active_id)

            client.send(:handle_explorer_open)
          end

          ws.on :message do |msg|
            next if client.send(:stale_explorer_connection?, active_id)

            client.send(:handle_explorer_message, msg.data)
          end

          ws.on :error do |e|
            next if client.send(:stale_explorer_connection?, active_id)

            client.send(:handle_explorer_error, e)
          end

          ws.on :close do |e|
            next if client.send(:stale_explorer_connection?, active_id)

            client.send(:handle_explorer_close, e)
          end
        end
      end

      def stale_explorer_connection?(id)
        id != @explorer_connection_id
      end

      def handle_explorer_open
        @explorer_connected = true
        @explorer_reconnect_attempts = 0
        flush_explorer_pending_subscriptions
        replay_explorer_subscriptions
      end

      def handle_explorer_message(raw)
        return if raw.nil? || raw.empty?
        return if raw.start_with?('Websocket connection established')

        data = parse_json(raw)
        return unless data

        if data.is_a?(Hash)
          return if data['channel'] == 'pong'

          return
        end

        unless data.is_a?(Array)
          warn '[Hyperliquid::WS] Unknown explorer WS message shape'
          return
        end

        return if data.empty?

        identifier = identify_explorer_array(data)
        return unless identifier

        enqueue_explorer_message(identifier, data)
      end

      def identify_explorer_array(data)
        first = data.first
        return unless first.is_a?(Hash)

        if first.key?('blockTime') && first.key?('hash') && first.key?('height') &&
           first.key?('numTxs') && first.key?('proposer')
          return 'explorerBlock'
        end

        if first.key?('action') && first.key?('block') && first.key?('error') &&
           first.key?('hash') && first.key?('time') && first.key?('user')
          return 'explorerTxs'
        end

        warn '[Hyperliquid::WS] Unknown explorer WS array shape'
        nil
      end

      def handle_explorer_error(error)
        warn "[Hyperliquid::WS] Explorer WS error: #{error.message}"
      end

      def handle_explorer_close(_event)
        was_connected = @explorer_connected
        @explorer_connected = false

        attempt_explorer_reconnect if was_connected && !@explorer_closing && @reconnect_enabled
      end

      def enqueue_explorer_message(identifier, data)
        @mutex.synchronize do
          if @explorer_queue.size >= @max_queue_size
            @explorer_dropped_message_count += 1
            if @explorer_dropped_message_count == 1 || (@explorer_dropped_message_count % 100).zero?
              warn "[Hyperliquid::WS] Explorer queue full (#{@max_queue_size}). " \
                   "Dropped #{@explorer_dropped_message_count} message(s)."
            end
            return
          end
        end
        @explorer_queue.push({ identifier: identifier, data: data })
      end

      def start_explorer_dispatch_thread
        @explorer_dispatch_thread = Thread.new do
          loop do
            msg = begin
              @explorer_queue.pop
            rescue ClosedQueueError
              break
            end
            break if msg.nil?

            callbacks = @mutex.synchronize { @explorer_subscriptions[msg[:identifier]]&.dup }
            next unless callbacks

            callbacks.each do |entry|
              entry[:callback].call(msg[:data])
            rescue StandardError => e
              warn "[Hyperliquid::WS] Explorer callback error: #{e.message}"
            end
          end
        end
        @explorer_dispatch_thread.name = 'hl-explorer-ws-dispatch'
      end

      def start_explorer_ping_thread
        @explorer_ping_thread = Thread.new do
          loop do
            sleep Constants::WS_PING_INTERVAL
            break if @explorer_closing

            send_explorer_json({ method: 'ping' }) if @explorer_connected
          end
        end
        @explorer_ping_thread.name = 'hl-explorer-ws-ping'
        @explorer_ping_thread.report_on_exception = false
      end

      def flush_explorer_pending_subscriptions
        pending = @mutex.synchronize do
          subs = @explorer_pending_subscriptions.dup
          @explorer_pending_subscriptions.clear
          subs
        end

        pending.each { |sub| send_explorer_subscribe(sub) }
      end

      def send_explorer_subscribe(subscription)
        send_explorer_json({ method: 'subscribe', subscription: subscription })
      end

      def send_explorer_unsubscribe(subscription)
        send_explorer_json({ method: 'unsubscribe', subscription: subscription })
      end

      def send_explorer_json(hash)
        @explorer_ws&.send(JSON.generate(hash))
      rescue StandardError => e
        warn "[Hyperliquid::WS] Explorer send error: #{e.message}"
      end

      def attempt_explorer_reconnect
        Thread.new do
          loop do
            break if @explorer_closing

            delay = [2**@explorer_reconnect_attempts, 30].min
            @explorer_reconnect_attempts += 1
            sleep delay

            break if @explorer_closing

            begin
              establish_explorer_connection
              break
            rescue StandardError => e
              warn "[Hyperliquid::WS] Explorer reconnect failed: #{e.message}"
            end
          end
        end
      end

      def replay_explorer_subscriptions
        subs = @mutex.synchronize do
          @explorer_subscription_msgs.values.map { |v| v[:subscription] }.uniq
        end
        subs.each { |sub| send_explorer_subscribe(sub) }
      end
    end
  end
end
