# frozen_string_literal: true

require 'prism'

# Static check of every SDK call made by the integration scripts, example.rb (including its
# commented Exchange block) and the ```ruby fences in README.md and docs/*.md: the method must
# exist and be public, and the literal arguments must fit its signature. The scripts only run
# live against testnet with a key, and the docs never run, so this is their only offline check.
module CallSurfaceCheck
  ACCESSORS = {
    info: Hyperliquid::Info,
    exchange: Hyperliquid::Exchange,
    ws: Hyperliquid::WS::Client
  }.freeze

  # Walks one source (a file, or every fence of one Markdown file in order, so a local assigned in
  # one fence is known in the next) and records the SDK calls it can resolve.
  class Scanner < Prism::Visitor
    Call = Struct.new(:label, :line, :owner, :name, :node)

    attr_reader :calls

    def initialize(label)
      super()
      @label = label
      @locals = {}
      @calls = []
    end

    def visit_local_variable_write_node(node)
      @locals.delete(node.name)
      owner = instance_owner(node.value)
      @locals[node.name] = owner if owner
      super
    end

    def visit_call_node(node)
      owner = receiver_owner(node.receiver)
      @calls << Call.new(@label, node.location.start_line, owner, node.name, node) if owner
      super
    end

    private

    # Class of the object a receiver expression evaluates to (an Info/Exchange/WS client), or the
    # Hyperliquid module/class itself for `Hyperliquid::Foo.bar` calls.
    def receiver_owner(receiver)
      case receiver
      when Prism::LocalVariableReadNode then @locals[receiver.name]
      when Prism::ConstantReadNode, Prism::ConstantPathNode then hyperliquid_constant(receiver)
      else instance_owner(receiver)
      end
    end

    # `<anything>.info` / `.exchange` / `.ws` with no arguments, or `Hyperliquid::X.new(...)`.
    def instance_owner(node)
      return unless node.is_a?(Prism::CallNode)
      return ACCESSORS[node.name] if accessor_call?(node)

      klass = constructed_class(node)
      klass if ACCESSORS.value?(klass)
    end

    def accessor_call?(node)
      node.receiver && node.arguments.nil? && ACCESSORS.key?(node.name)
    end

    def constructed_class(node)
      node.name == :new && node.receiver && hyperliquid_constant(node.receiver)
    end

    def hyperliquid_constant(node)
      return unless node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)

      name = node.full_name
      return unless name == 'Hyperliquid' || name.start_with?('Hyperliquid::')

      value = Object.const_get(name)
      value if value.is_a?(Module)
    rescue NameError
      nil
    end
  end

  module_function

  # Returns a problem string for the call, or nil when it fits the real signature.
  def problem(call)
    where = "#{call.label}:#{call.line}: #{call.owner}#{singleton_call?(call) ? '.' : '#'}#{call.name}"
    method = resolve(call)
    return "#{where} is not a public method" unless method

    params = method.parameters
    args, keywords = split_arguments(call.node.arguments&.arguments || [], params)
    detail = positional_problem(args, params) || keyword_problem(keywords, params)
    "#{where} #{detail}" if detail
  end

  def singleton_call?(call)
    call.node.receiver.is_a?(Prism::ConstantReadNode) || call.node.receiver.is_a?(Prism::ConstantPathNode)
  end

  def resolve(call)
    owner = call.owner
    if singleton_call?(call)
      return owner.instance_method(:initialize) if call.name == :new && owner.is_a?(Class)

      owner.respond_to?(call.name) ? owner.method(call.name) : nil
    elsif owner.public_method_defined?(call.name)
      owner.instance_method(call.name)
    end
  end

  # A trailing `k: v` hash binds to keywords only when the method takes keywords.
  def split_arguments(args, params)
    takes_keywords = params.any? { |type, _| %i[key keyreq keyrest].include?(type) }
    return [args, nil] unless takes_keywords && args.last.is_a?(Prism::KeywordHashNode)

    [args[0...-1], args.last]
  end

  def positional_problem(args, params)
    return if args.any? { |a| a.is_a?(Prism::SplatNode) || a.is_a?(Prism::ForwardingArgumentsNode) }

    required = names(params, :req).size
    max = names(params, :rest).any? ? Float::INFINITY : required + names(params, :opt).size
    return if args.size.between?(required, max)

    "takes #{required}..#{max} positional arguments, called with #{args.size}"
  end

  def keyword_problem(hash, params)
    literal, dynamic = literal_keywords(hash)
    unknown = names(params, :keyrest).any? ? [] : literal - names(params, :key, :keyreq)
    return "has unknown keyword(s) #{unknown.join(', ')}" if unknown.any?

    missing = dynamic ? [] : names(params, :keyreq) - literal
    "is missing required keyword(s) #{missing.join(', ')}" if missing.any?
  end

  # Literal symbol keys, and whether any key is dynamic (`**opts` or a non-symbol key).
  def literal_keywords(hash)
    elements = hash ? hash.elements : []
    literal = elements.filter_map do |element|
      element.key.unescaped.to_sym if element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
    end
    [literal, literal.size != elements.size]
  end

  # Parameter names of the given kinds (anonymous `*`/`**` still count: their name is non-nil or `true`).
  def names(params, *types)
    params.filter_map { |type, name| name || true if types.include?(type) }
  end
end

RSpec.describe 'SDK call surface of scripts, example.rb and docs' do
  root = File.expand_path('..', __dir__)
  sdk_call = /\b(?:sdk|exchange|info)\./
  scanners = []
  unparsable = []

  scan = lambda do |label, fragments|
    scanner = CallSurfaceCheck::Scanner.new(label)
    fragments.each do |code, line|
      result = Prism.parse(code, line: line)
      if result.success?
        result.value.accept(scanner)
      elsif code.match?(sdk_call)
        unparsable << "#{label}:#{line}: #{result.errors.first.message}"
      end
    end
    scanners << scanner
  end

  Dir[File.join(root, 'scripts/*.rb')].each do |path|
    scan.call("scripts/#{File.basename(path)}", [[File.read(path), 1]])
  end

  example = File.read(File.join(root, 'example.rb'))
  scan.call('example.rb', [[example, 1]])
  # The commented Exchange block: code lines are `#   code`. Keep line numbers by blanking prose lines.
  commented = example.lines.map { |l| l.start_with?('#   ') ? l.delete_prefix('# ') : "\n" }.join
  scan.call('example.rb (commented block)', [[commented, 1]])

  ([File.join(root, 'README.md')] + Dir[File.join(root, 'docs/*.md')]).each do |path|
    fences = []
    File.read(path).scan(/^```ruby\n(.*?)^```/m) do
      body = Regexp.last_match(1)
      line = Regexp.last_match.pre_match.count("\n") + 2
      fences << [body, line]
    end
    scan.call(path.delete_prefix("#{root}/"), fences)
  end

  calls = scanners.flat_map(&:calls)

  it 'parses every script, the commented example block, and every fence that calls the SDK' do
    expect(unparsable).to be_empty
  end

  it 'finds enough SDK calls that the scan cannot silently go vacuous' do
    expect(calls.size).to be >= 300 # 403 on 2026-10-02
  end

  scanners.each do |scanner|
    next if scanner.calls.empty?

    it "#{scanner.calls.first.label} calls only public SDK methods with arguments matching their signatures" do
      expect(scanner.calls.filter_map { |call| CallSurfaceCheck.problem(call) }).to be_empty
    end
  end

  describe 'docs/DEVELOPMENT.md integration script table' do
    scripts = Dir[File.join(root, 'scripts/test_[0-9][0-9]_*.rb')].map { |p| File.basename(p) }.sort
    rows = File.read(File.join(root, 'docs/DEVELOPMENT.md')).scan(/^\| `(test_\w+\.rb)` \|/).flatten

    it 'has exactly one row for every scripts/test_NN_*.rb' do
      counts = rows.tally
      expect(scripts.reject { |s| counts[s] == 1 }).to be_empty
    end

    it 'names only scripts that exist' do
      expect(rows - scripts).to be_empty
    end
  end
end
