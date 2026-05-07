# frozen_string_literal: true

require 'msgpack'

module Hyperliquid
  module Signing
    # Multi-signature action helpers — submitter envelope construction and co-signer signing.
    #
    # Mirrors the official Python SDK's three multi-sig flows:
    #   1. `Exchange#multi_sig` (the submitter — signs the outer envelope)
    #   2. `sign_as_co_signer_l1`        — co-signer for L1 inner actions (orders, cancels, etc.)
    #   3. `sign_as_co_signer_user_signed` — co-signer for user-signed inner actions
    #                                       (sendAsset, usdSend, etc.)
    #
    # Co-signature collection is the caller's responsibility — these helpers produce a single
    # co-signer signature; the submitter then assembles the array and posts the envelope.
    module MultiSig
      OUTER_PRIMARY_TYPE = 'HyperliquidTransaction:SendMultiSig'

      # Build the outer multi-sig envelope (the action body posted to /exchange).
      # @param inner_action [Hash] The wrapped action (any L1 or user-signed action body)
      # @param multi_sig_user [String] Address of the multi-sig user (lowercased)
      # @param outer_signer [String] Address of the submitter (lowercased)
      # @param signatures [Array<Hash>] Pre-collected co-signer signatures
      # @return [Hash] Multi-sig envelope ready for signing + posting
      def self.build_envelope(inner_action:, multi_sig_user:, outer_signer:, signatures:)
        {
          type: 'multiSig',
          signatureChainId: '0x66eee',
          signatures: signatures,
          payload: {
            multiSigUser: multi_sig_user.downcase,
            outerSigner: outer_signer.downcase,
            action: inner_action
          }
        }
      end

      # Compute the multiSigActionHash that the submitter signs over.
      # Mirrors Python's `sign_multi_sig_action`: action_hash(envelope - type, vault, nonce, expires).
      # @param envelope [Hash] The multi-sig envelope (will have :type stripped before hashing)
      # @param nonce [Integer] Nonce timestamp (ms)
      # @param vault_address [String, nil] Optional vault address
      # @param expires_after [Integer, nil] Optional expiration timestamp (ms)
      # @return [String] 0x-prefixed 32-byte hex hash
      def self.envelope_action_hash(envelope:, nonce:, vault_address: nil, expires_after: nil)
        without_type = envelope.dup
        without_type.delete(:type)
        Signer.compute_action_hash(without_type, nonce, vault_address: vault_address,
                                                        expires_after: expires_after)
      end

      # Co-signer flow for L1 inner actions (orders, cancels, leverage, etc.).
      # The signed payload is the list `[multi_sig_user, outer_signer, action]`, hashed and
      # signed via the L1 phantom-agent flow.
      #
      # @param signer [Signer] Co-signer's wallet
      # @param inner_action [Hash] The wrapped L1 action
      # @param multi_sig_user [String] Multi-sig user address
      # @param outer_signer [String] Submitter address (NOT the co-signer's address)
      # @param nonce [Integer] Nonce timestamp (ms)
      # @param vault_address [String, nil] Optional vault address
      # @param expires_after [Integer, nil] Optional expiration timestamp (ms)
      # @return [Hash] Signature with :r, :s, :v
      def self.sign_as_co_signer_l1(signer:, inner_action:, multi_sig_user:, outer_signer:, nonce:,
                                    vault_address: nil, expires_after: nil)
        envelope = [multi_sig_user.downcase, outer_signer.downcase, inner_action]
        signer.sign_l1_action(envelope, nonce, vault_address: vault_address,
                                               expires_after: expires_after)
      end

      # Co-signer flow for user-signed inner actions (sendAsset, usdSend, etc.).
      # Enriches the inner action with `payloadMultiSigUser` + `outerSigner` fields and the
      # corresponding type entries, then signs via the user-signed typed-data flow.
      #
      # @param signer [Signer] Co-signer's wallet
      # @param inner_action [Hash] The wrapped user-signed action body
      # @param multi_sig_user [String] Multi-sig user address
      # @param outer_signer [String] Submitter address
      # @param primary_type [String] Inner action's EIP-712 primary type (e.g. 'HyperliquidTransaction:SendAsset')
      # @param sign_types [Hash] Inner action's EIP-712 type definitions
      # @return [Hash] Signature with :r, :s, :v
      def self.sign_as_co_signer_user_signed(signer:, inner_action:, multi_sig_user:, outer_signer:,
                                             primary_type:, sign_types:)
        enriched_action = inner_action.merge(
          payloadMultiSigUser: multi_sig_user.downcase,
          outerSigner: outer_signer.downcase
        )
        enriched_types = enrich_user_signed_types(sign_types)
        signer.sign_user_signed_action(enriched_action, primary_type, enriched_types)
      end

      # Insert payloadMultiSigUser + outerSigner type entries immediately after hyperliquidChain.
      # Matches Python SDK's `add_multi_sig_types`.
      def self.enrich_user_signed_types(sign_types)
        sign_types.each_with_object({}) do |(key, fields), result|
          new_fields = []
          fields.each do |f|
            new_fields << f
            if f[:name].to_s == 'hyperliquidChain'
              new_fields << { name: :payloadMultiSigUser, type: 'address' }
              new_fields << { name: :outerSigner, type: 'address' }
            end
          end
          result[key] = new_fields
        end
      end
      private_class_method :enrich_user_signed_types
    end
  end
end
