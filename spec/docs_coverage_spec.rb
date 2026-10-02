# frozen_string_literal: true

# Keeps docs/API.md and docs/WS.md in step with the public API. A method counts as
# documented only when its H2 section has a list item starting with `name(` or `name`
# (receiver prefix allowed) whose backticked signature names every parameter.
RSpec.describe 'API documentation coverage' do
  root = File.expand_path('..', __dir__)
  api_md = File.read(File.join(root, 'docs/API.md'))
  ws_md = File.read(File.join(root, 'docs/WS.md'))

  section = lambda do |title|
    match = api_md.match(/^## #{Regexp.escape(title)}\n(.*?)(?=^## |\z)/m)
    raise "docs/API.md has no '## #{title}' section" unless match

    match[1]
  end

  entries = lambda do |text|
    text.scan(/^- `(?:[A-Z][\w:]*\.)?([a-z_][a-z0-9_]*[?!=]?)([^`]*)`/).to_h
  end

  # [H2 title, owner, singleton methods?, names deliberately left out (with reason)]
  surfaces = [
    ['SDK', Hyperliquid, true, []],
    ['SDK', Hyperliquid::SDK, false, []],
    ['Info', Hyperliquid::Info, false, []],
    ['Exchange', Hyperliquid::Exchange, false, []],
    ['WebSocket', Hyperliquid::WS::Client, false, []],
    ['Client Order IDs (Cloid)', Hyperliquid::Cloid, true, []],
    # Ruby object protocol, not SDK API.
    ['Client Order IDs (Cloid)', Hyperliquid::Cloid, false, %i[to_s inspect == eql? hash]],
    # Internal helpers used by Exchange#multi_sig.
    ['Multi-Sig Co-Signing', Hyperliquid::Signing::MultiSig, true,
     %i[build_envelope payload_action envelope_action_hash]]
  ]

  surfaces.each do |title, owner, singleton, excluded|
    names = singleton ? owner.singleton_methods(false) : owner.public_instance_methods(false)
    (names - excluded).sort.each do |name|
      it "documents #{owner}#{singleton ? '.' : '#'}#{name} under '## #{title}'" do
        documented = entries.call(section.call(title))
        expect(documented).to have_key(name.to_s)

        method = singleton ? owner.method(name) : owner.instance_method(name)
        signature = documented[name.to_s]
        method.parameters.each do |kind, param|
          next if param.nil? || kind == :block

          pattern = %i[key keyreq].include?(kind) ? /\b#{param}:/ : /\b#{param}\b/
          expect(signature).to match(pattern), "#{name}: parameter #{param} missing from `#{name}#{signature}`"
        end
      end
    end
  end

  # Main-API subscription types. The WS-parity refactor replaces the `case` in
  # `subscription_identifier` with the ROUTING_KEYS table; once it lands, delete the
  # source-regex branch below.
  ws_client = Hyperliquid::WS::Client
  channels =
    if ws_client.const_defined?(:ROUTING_KEYS, false)
      ws_client.const_get(:ROUTING_KEYS, false).keys
    else
      File.read(File.join(root, 'lib/hyperliquid/ws/client.rb'))[/def subscription_identifier.*?\n      end\n/m]
          .scan(/^\s+when (.+?)(?: then|$)/).flatten
          .flat_map { |list| list.scan(/'([A-Za-z0-9]+)'/).flatten }
    end

  it 'finds the supported main-API channels' do
    expect(channels).to include('l2Book', 'allMids')
  end

  channels.each do |channel|
    it "documents the #{channel} channel in docs/API.md and docs/WS.md" do
      api_row = section.call('WebSocket').match?(/^\| `#{channel}` \|/)
      ws_row = ws_md.match?(/^\| `#{channel}`/)
      expect(api_row).to be(true), "docs/API.md WebSocket table lacks #{channel}"
      expect(ws_row).to be(true), "docs/WS.md routing table lacks #{channel}"
    end
  end
end
