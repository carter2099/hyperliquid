# frozen_string_literal: true

require 'json'
require 'msgpack'
require 'eth'
require 'digest/keccak'

module Hyperliquid
  # Native Ruby signing utilities (EIP-712 + keccak + msgpack) for Hyperliquid.
  module Signing
    # --- Public API ---------------------------------------------------------

    # Sign an L1 trading action (e.g., place order) using an Ethereum private key.
    # This follows the Hyperliquid L1 scheme: msgpack the payload, keccak256 it,
    # then sign typed data containing the action hash and nonce.
    #
    # @param private_key [String] 0x-prefixed private key
    # @param action [Hash] Canonical action payload (string/symbol keys ok)
    # @param nonce [Integer] Millisecond nonce
    # @param vault_address [String, nil] Optional vault address (not embedded in types by default)
    # @param is_mainnet [Boolean] Whether to use mainnet domain when signing (reserved)
    # @return [String] 0x-prefixed signature (65-byte RSV)
    def self.sign_l1_action(private_key:, action:, nonce:, vault_address: nil, is_mainnet: false)
      action_str_keys = stringify_keys(action)
      payload = { 'action' => action_str_keys, 'nonce' => nonce }
      payload['vaultAddress'] = vault_address.downcase if vault_address

      msgpack_bytes = MessagePack.pack(payload)
      action_hash_bin = keccak256(msgpack_bytes)
      action_hash_hex = '0x' + action_hash_bin.unpack1('H*')

      domain = default_l1_domain
      types = default_l1_types
      message = { 'actionHash' => action_hash_hex, 'nonce' => nonce }

      digest = eip712_digest(domain: domain, types: types, primary_type: 'L1Action', message: message)
      sign_digest(private_key, digest)
    end

    # --- EIP-712 helpers ----------------------------------------------------

    def self.eip712_digest(domain:, types:, primary_type:, message:)
      domain_sep = domain_separator(domain, types)
      msg_hash = hash_struct(primary_type, types, message)
      keccak256("\x19\x01" + domain_sep + msg_hash)
    end

    def self.domain_separator(domain, types)
      hash_struct('EIP712Domain', types, domain)
    end

    def self.hash_struct(primary_type, types, data)
      encoded = encode_data(primary_type, types, data)
      keccak256(encoded)
    end

    def self.encode_data(primary_type, types, data)
      type_hash_bin = keccak256(encode_type(primary_type, types))
      enc_values = [type_hash_bin]

      field_types = types.fetch(primary_type) { raise ArgumentError, "Unknown type #{primary_type}" }
      field_types.each do |field|
        name = field['name'] || field[:name]
        type = field['type'] || field[:type]
        value = data[name] || data[name.to_sym]
        enc_values << encode_value(type, value, types)
      end

      enc_values.join
    end

    def self.encode_type(primary_type, types)
      deps = collect_dependencies(primary_type, types)
      deps.delete('EIP712Domain')
      # Primary type first, then sorted deps
      ordered = [primary_type] + deps.sort
      ordered.uniq.map do |type|
        fields = types[type]
        inner = fields.map { |f| "#{f['type'] || f[:type]} #{f['name'] || f[:name]}" }.join(',')
        "#{type}(#{inner})"
      end.join
    end

    def self.collect_dependencies(type, types, collected = {})
      return collected.keys if collected[type]

      collected[type] = true
      fields = types[type] || []
      fields.each do |f|
        t = (f['type'] || f[:type]).to_s
        next if primitive_type?(t)

        base = t.sub(/\[\]$/, '')
        collect_dependencies(base, types, collected)
      end
      collected.keys
    end

    def self.primitive_type?(type)
      %w[uint256 address bytes32 string bytes bool].include?(type) || type.end_with?('[]')
    end

    def self.encode_value(type, value, types)
      if type.end_with?('[]')
        base = type.sub(/\[\]$/, '')
        # Per EIP-712, arrays are hashed as keccak256(concat(encode_value(base, v)))
        inner = (value || []).map { |v| encode_value(base, v, types) }.join
        keccak256(inner)
      else
        case type
        when 'uint256'
          left_pad_uint256(value.to_i)
        when 'address'
          left_pad_address(value)
        when 'bytes32'
          left_pad_bytes32(value)
        when 'bool'
          left_pad_uint256(value ? 1 : 0)
        when 'string'
          keccak256(value.to_s)
        when 'bytes'
          keccak256(hex_to_bin(value))
        else
          # user-defined type
          keccak256(encode_data(type, types, value))
        end
      end
    end

    # --- Low-level helpers --------------------------------------------------

    def self.keccak256(data)
      Digest::Keccak.digest(data, 256)
    end

    def self.hex_to_bin(val)
      return ''.b if val.nil?

      v = val.to_s
      v = v.sub(/^0x/, '')
      [v].pack('H*')
    end

    def self.left_pad_uint256(n)
      hex = n.to_i.to_s(16)
      hex = hex.rjust(64, '0')
      [hex].pack('H*')
    end

    def self.left_pad_bytes32(val)
      hex = val.to_s.sub(/^0x/, '')
      hex = hex.rjust(64, '0')
      [hex].pack('H*')
    end

    def self.left_pad_address(addr)
      a = (addr || '').to_s.downcase.sub(/^0x/, '')
      a = a.rjust(40, '0')
      # left pad to 32 bytes
      (('0' * 24) + a).scan(/../).map { |h| h.hex.chr }.join
    end

    def self.sign_digest(private_key_hex, digest_bin)
      key = Eth::Key.new(priv: private_key_hex)
      sig_hex = key.sign(digest_bin)
      Eth::Util.prefixed?(sig_hex) ? sig_hex : Eth::Util.prefix_hex(sig_hex)
    end

    # --- Defaults -----------------------------------------------------------

    def self.default_l1_domain
      {
        'name' => 'Exchange',
        'version' => '1',
        'chainId' => 1337
      }
    end

    def self.default_l1_types
      {
        'EIP712Domain' => [
          { 'name' => 'name', 'type' => 'string' },
          { 'name' => 'version', 'type' => 'string' },
          { 'name' => 'chainId', 'type' => 'uint256' }
        ],
        'L1Action' => [
          { 'name' => 'actionHash', 'type' => 'bytes32' },
          { 'name' => 'nonce', 'type' => 'uint256' }
        ]
      }
    end

    def self.stringify_keys(obj)
      case obj
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
      when Array
        obj.map { |v| stringify_keys(v) }
      else
        obj
      end
    end
  end
end
