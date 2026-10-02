# frozen_string_literal: true

require 'spec_helper'
require 'socket'
require 'websocket'

# One accepted server-side WebSocket connection (websocket gem handshake + framing): completes
# the upgrade, then queues the decoded frames the client sends.
class LoopbackWSConnection
  def initialize(socket)
    @socket = socket
    @frames = Queue.new
    handshake = WebSocket::Handshake::Server.new
    handshake << socket.readpartial(4096) until handshake.finished?
    raise "bad client handshake: #{handshake.error}" unless handshake.valid?

    socket.write(handshake.to_s)
    @version = handshake.version
    @reader = Thread.new { read_frames }
  end

  # Next text frame from the client; raises if none arrives within `timeout`.
  def next_text(timeout: 2)
    loop do
      frame = @frames.pop(timeout: timeout)
      raise "no text frame from the client within #{timeout}s" unless frame
      return frame.data if frame.type == :text
    end
  end

  def send_text(text)
    @socket.write(WebSocket::Frame::Outgoing::Server.new(version: @version, data: text, type: :text).to_s)
  end

  # Server-side close without a close frame, as on a dropped connection.
  def drop
    @socket.close
    @reader.join(2)
  end

  private

  def read_frames
    incoming = WebSocket::Frame::Incoming::Server.new(version: @version)
    loop do
      incoming << @socket.readpartial(4096)
      while (frame = incoming.next)
        @frames << frame
      end
    end
  rescue IOError, SystemCallError
    @frames.close
  end
end

# Real ws_lite client against a local server: exercises TCP connect, the HTTP upgrade, frame
# encode/decode, and reconnect, none of which the fake-socket specs in client_spec.rb touch.
RSpec.describe Hyperliquid::WS::Client, 'over a loopback socket' do
  let(:server) { TCPServer.new('127.0.0.1', 0) }
  let(:connections) { Queue.new }
  let(:client) do
    described_class.new.tap do |c|
      c.instance_variable_set(:@url, "ws://127.0.0.1:#{server.addr[1]}/ws")
    end
  end
  let(:eth_subscribe) { '{"method":"subscribe","subscription":{"type":"l2Book","coin":"ETH"}}' }

  def next_connection
    connections.pop(timeout: 2) || raise('client did not connect within 2s')
  end

  before do
    acceptor = Thread.new do
      loop { connections << LoopbackWSConnection.new(server.accept) }
    rescue IOError, SystemCallError
      nil
    end
    acceptor.report_on_exception = false
    # Reconnect backoff returns at once; the 50 s ping sleep stays real.
    allow(client).to receive(:sleep).and_wrap_original do |original, seconds|
      original.call(seconds) if seconds == Hyperliquid::Constants::WS_PING_INTERVAL
    end
  end

  after do
    client.close
    server.close
  end

  it 'writes the subscribe and unsubscribe frames byte for byte' do
    id = client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |_d| }
    connection = next_connection

    expect(connection.next_text).to eq(eth_subscribe)
    client.unsubscribe(id)
    expect(connection.next_text).to eq('{"method":"unsubscribe","subscription":{"type":"l2Book","coin":"ETH"}}')
  end

  it 'delivers an inbound UTF-8 channel frame to the callback' do
    received = Queue.new
    client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }
    connection = next_connection
    expect(connection.next_text).to eq(eth_subscribe)

    connection.send_text('{"channel":"l2Book","data":{"coin":"ETH","levels":[],"name":"Ünï €"}}')

    expect(received.pop(timeout: 2)).to eq({ 'coin' => 'ETH', 'levels' => [], 'name' => 'Ünï €' })
  end

  it 'reconnects after the server drops the connection and re-sends the subscription' do
    received = Queue.new
    client.subscribe({ type: 'l2Book', coin: 'ETH' }) { |d| received << d }
    first = next_connection
    expect(first.next_text).to eq(eth_subscribe)

    first.drop
    second = next_connection

    expect(second.next_text).to eq(eth_subscribe)
    second.send_text('{"channel":"l2Book","data":{"coin":"ETH","levels":[]}}')
    expect(received.pop(timeout: 2)).to eq({ 'coin' => 'ETH', 'levels' => [] })
    expect(client).to be_connected
  end
end
