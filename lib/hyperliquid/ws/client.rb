# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'

module Hyperliquid
  module WS
    # Managed WebSocket client for subscribing to real-time data channels
    class Client
      attr_reader :dropped_message_count

      def initialize(testnet: false, max_queue_size: Constants::WS_MAX_QUEUE_SIZE, reconnect: true)
        base_url = testnet ? Constants::TESTNET_API_URL : Constants::MAINNET_API_URL
        @url = base_url.sub(%r{^https?://}, 'wss://') + Constants::WS_ENDPOINT
        @max_queue_size = max_queue_size
        @reconnect_enabled = reconnect

        @subscriptions = {}      # identifier => [{ id:, callback: }]
        @subscription_msgs = {}  # subscription_id => { subscription:, identifier: }
        @next_id = 0
        @mutex = Mutex.new
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
      end

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

      def unsubscribe(subscription_id)
        sub_msg = nil
        should_send = false

        @mutex.synchronize do
          sub_msg = @subscription_msgs.delete(subscription_id)
          return unless sub_msg

          identifier = sub_msg[:identifier]
          callbacks = @subscriptions[identifier]
          return unless callbacks

          callbacks.reject! { |entry| entry[:id] == subscription_id }

          if callbacks.empty?
            @subscriptions.delete(identifier)
            should_send = true
          end
        end

        send_unsubscribe(sub_msg[:subscription]) if should_send && @connected
      end

      def close
        @closing = true
        @connected = false

        @ping_thread&.kill
        @ping_thread = nil

        @queue&.close if @queue.respond_to?(:close)
        @dispatch_thread&.join(5)
        @dispatch_thread = nil

        @ws&.close
        @ws = nil
      end

      def connected?
        @connected
      end

      def on(event, &callback)
        @lifecycle_callbacks[event] = callback
      end

      private

      def establish_connection
        client = self
        url = @url

        @ws = ::WebSocket::Client::Simple.connect(url) do |ws|
          ws.on :open do
            client.send(:handle_open)
          end

          ws.on :message do |msg|
            client.send(:handle_message, msg.data)
          end

          ws.on :error do |e|
            client.send(:handle_error, e)
          end

          ws.on :close do |e|
            client.send(:handle_close, e)
          end
        end
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
        when 'l2Book'   then "l2Book:#{data['coin'].downcase}"
        when 'allMids'  then 'allMids'
        when 'trades'   then data.is_a?(Array) && data[0] ? "trades:#{data[0]['coin'].downcase}" : nil
        end
      end

      def subscription_identifier(subscription)
        type = subscription[:type] || subscription['type']
        case type
        when 'l2Book'
          coin = subscription[:coin] || subscription['coin']
          "l2Book:#{coin.downcase}"
        when 'allMids'
          'allMids'
        when 'trades'
          coin = subscription[:coin] || subscription['coin']
          "trades:#{coin.downcase}"
        else
          raise Hyperliquid::WebSocketError, "Unsupported subscription type: #{type}"
        end
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
    end
  end
end
