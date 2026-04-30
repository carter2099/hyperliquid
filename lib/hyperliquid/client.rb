# frozen_string_literal: true

require 'faraday'
require 'faraday/retry'
require 'json'

module Hyperliquid
  # HTTP client for making requests to Hyperliquid API
  class Client
    # Default retry configuration for API requests
    DEFAULT_RETRY_OPTIONS = {
      max: 2,
      interval: 0.5,
      interval_randomness: 0.5,
      backoff_factor: 2,
      retry_statuses: [429, 502, 503, 504],
      exceptions: [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError
      ]
    }.freeze

    # Initialize a new HTTP client
    # @param base_url [String] The base URL for the default API (info/exchange)
    # @param timeout [Integer] Request timeout in seconds (default: Constants::DEFAULT_TIMEOUT)
    # @param retry_enabled [Boolean] Whether to enable retry logic (default: false)
    # @param explorer_base_url [String, nil] Optional base URL for the explorer RPC (used by
    #   tx_details / user_details). When nil, calls with target: :explorer raise ConfigurationError.
    def initialize(base_url:, timeout: Constants::DEFAULT_TIMEOUT, retry_enabled: false,
                   explorer_base_url: nil)
      @retry_enabled = retry_enabled
      @timeout = timeout
      @explorer_base_url = explorer_base_url
      @connection = build_connection(base_url)
      @explorer_connection = nil
    end

    # Make a POST request to the API
    # @param endpoint [String] The API endpoint to make the request to
    # @param body [Hash] The request body as a hash (default: {})
    # @param target [Symbol] Which connection to use; :default (info/exchange) or :explorer (RPC)
    # @return [Hash, String] The parsed JSON response or raw response body
    # @raise [NetworkError] When connection fails
    # @raise [TimeoutError] When request times out
    # @raise [BadRequestError] When API returns 400 status
    # @raise [AuthenticationError] When API returns 401 status
    # @raise [NotFoundError] When API returns 404 status
    # @raise [RateLimitError] When API returns 429 status
    # @raise [ServerError] When API returns 5xx status
    # @raise [ClientError] When API returns unexpected status
    # @raise [ConfigurationError] When target: :explorer is requested but no explorer_base_url was configured
    def post(endpoint, body = {}, target: :default)
      connection = connection_for(target)
      response = connection.post(endpoint) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = body.to_json unless body.empty?
      end

      handle_response(response)
    rescue Faraday::RetriableResponse => e
      # After retries are exhausted, Faraday throws a RetriableResponse
      # Catch and handle that here to bubble up the actual network error
      handle_response(e.response)
    rescue Faraday::ConnectionFailed => e
      raise NetworkError, "Connection failed: #{e.message}"
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Request timed out: #{e.message}"
    end

    private

    def connection_for(target)
      case target
      when :default
        @connection
      when :explorer
        unless @explorer_base_url
          raise ConfigurationError,
                'Explorer RPC URL not configured; pass explorer_base_url: when constructing the Client'
        end
        @explorer_connection ||= build_connection(@explorer_base_url)
      else
        raise ArgumentError, "Unknown post target: #{target.inspect} (expected :default or :explorer)"
      end
    end

    def build_connection(base_url)
      Faraday.new(url: base_url) do |conn|
        conn.options.timeout = @timeout
        conn.options.read_timeout = Constants::DEFAULT_READ_TIMEOUT
        conn.request :retry, DEFAULT_RETRY_OPTIONS if @retry_enabled
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
