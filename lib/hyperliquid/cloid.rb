# frozen_string_literal: true

require 'securerandom'

module Hyperliquid
  # Client Order ID for tracking orders
  # Must be a 16-byte hex string in format: 0x + 32 hex characters
  class Cloid
    # Initialize a new Cloid from a raw hex string
    # @param raw_cloid [String] Hex string in format 0x + 32 hex characters
    # @raise [ArgumentError] If format is invalid
    def initialize(raw_cloid)
      @raw_cloid = raw_cloid.downcase
      validate!
    end

    # Get the raw hex string representation
    # @return [String] The raw cloid string
    def to_raw
      @raw_cloid
    end

    # String representation
    # @return [String] The raw cloid string
    def to_s
      @raw_cloid
    end

    # Inspect representation
    # @return [String] The raw cloid string
    def inspect
      @raw_cloid
    end

    # Equality check
    # @param other [Cloid, String] Another Cloid or string to compare
    # @return [Boolean] True if equal
    def ==(other)
      case other
      when Cloid
        @raw_cloid == other.to_raw
      when String
        @raw_cloid == other.downcase
      else
        false
      end
    end

    alias eql? ==

    # Hash for use in Hash keys
    # @return [Integer] Hash value
    def hash
      @raw_cloid.hash
    end

    class << self
      # Create a Cloid from an integer
      # @param value [Integer] Integer value (0 to 2^128-1)
      # @return [Cloid] New Cloid instance
      # @raise [ArgumentError] If value is out of range
      def from_int(value)
        raise ArgumentError, 'cloid integer must be non-negative' if value.negative?
        raise ArgumentError, 'cloid integer must be less than 2^128' if value >= 2**128

        new(format('0x%032x', value))
      end

      # Create a Cloid from a hex string
      # @param value [String] Hex string in format 0x + 32 hex characters
      # @return [Cloid] New Cloid instance
      def from_str(value)
        new(value)
      end

      # Generate a random Cloid
      # @return [Cloid] New random Cloid instance
      def random
        from_int(SecureRandom.random_number(2**128))
      end

      # Create a Cloid from a UUID string
      # @param uuid [String] UUID string (with or without dashes)
      # @return [Cloid] New Cloid instance
      def from_uuid(uuid)
        hex = uuid.delete('-').downcase
        raise ArgumentError, 'UUID must be 32 hex characters' unless hex.match?(/\A[0-9a-f]{32}\z/)

        new("0x#{hex}")
      end
    end

    private

    def validate!
      return if @raw_cloid.match?(/\A0x[0-9a-f]{32}\z/)

      raise ArgumentError,
            "cloid must be '0x' followed by 32 hex characters (16 bytes). Got: #{@raw_cloid.inspect}"
    end
  end
end
