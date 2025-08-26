# frozen_string_literal: true

module Hyperliquid
  # Base error class for all Hyperliquid SDK errors
  class Error < StandardError
    attr_reader :status_code, :response_body

    def initialize(message, status_code: nil, response_body: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
    end
  end

  # Error for HTTP client issues
  class ClientError < Error; end

  # Error for server-side issues
  class ServerError < Error; end

  # Error for authentication issues
  class AuthenticationError < ClientError; end

  # Error for rate limiting
  class RateLimitError < ClientError; end

  # Error for bad requests
  class BadRequestError < ClientError; end

  # Error for not found resources
  class NotFoundError < ClientError; end

  # Error for connection timeouts
  class TimeoutError < Error; end

  # Error for network connectivity issues
  class NetworkError < Error; end
end
