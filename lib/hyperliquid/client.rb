# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module Hyperliquid
  # HTTP client for making requests to Hyperliquid API
  class Client
    # TODO:
    # Unused for now. To be added to build_connection
    DEFAULT_RETRY_OPTIONS = {
      max: 2,
      interval: 0.5,
      interval_randomness: 0.5,
      backoff_factor: 2,
      retry_statuses: [502, 503, 504],
      exceptions: [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError
      ]
    }.freeze

    def initialize(base_url:, timeout: Constants::DEFAULT_TIMEOUT)
      @connection = build_connection(base_url, timeout)
    end

    # Make a POST request to the API
    def post(endpoint, body = {})
      response = @connection.post(endpoint) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json unless body.empty?
      end

      handle_response(response)
    rescue Faraday::ConnectionFailed => e
      raise NetworkError, "Connection failed: #{e.message}"
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Request timed out: #{e.message}"
    end

    private

    def build_connection(base_url, timeout)
      Faraday.new(url: base_url) do |conn|
        conn.options.timeout = timeout
        conn.options.read_timeout = Constants::DEFAULT_READ_TIMEOUT

        # TODO:
        # conn.request :retry, DEFAULT_RETRY_OPTIONS
      end
    end

    def handle_response(response)
      parsed_body = parse_json(response.body)

      case response.status
      when 200..299
        parsed_body
      when 400
        raise BadRequestError.new(
          'Bad request',
          status_code: response.status,
          response_body: parsed_body
        )
      when 401
        raise AuthenticationError.new(
          'Authentication failed',
          status_code: response.status,
          response_body: parsed_body
        )
      when 404
        raise NotFoundError.new(
          'Resource not found',
          status_code: response.status,
          response_body: parsed_body
        )
      when 429
        raise RateLimitError.new(
          'Rate limit exceeded',
          status_code: response.status,
          response_body: parsed_body
        )
      when 500..599
        raise ServerError.new(
          'Server error',
          status_code: response.status,
          response_body: parsed_body
        )
      else
        raise ClientError.new(
          "Unexpected response status: #{response.status}",
          status_code: response.status,
          response_body: parsed_body
        )
      end
    end

    def parse_json(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
