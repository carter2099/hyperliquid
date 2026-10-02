# frozen_string_literal: true

# Method-coverage gate: a full `rspec` run fails when a public method of the SDK's API classes
# never executed. Catches a new public method landing without any spec. Only line-level presence
# is checked; assertion strength is the job of the specs themselves.
#
# Coverage must start before `require 'hyperliquid'`; spec_helper requires this file first.
require 'coverage'

# Load lib's third-party/stdlib dependencies first so Coverage only tracks code loaded afterwards.
# Coverage.peek_result keys its method table by [class, ...] arrays, and some dependencies
# (eth's Eth::Abi::Encoder.hash(type, arg)) override `hash`, which would crash building the result.
Dir[File.expand_path('../../lib/**/*.rb', __dir__)].each do |file|
  File.foreach(file) do |line|
    feature = line[/\A\s*require\s+['"]([^'"]+)['"]/, 1]
    require feature if feature && !feature.start_with?('hyperliquid')
  end
end

Coverage.start(methods: true) unless Coverage.running?

module MethodCoverage
  LIB_DIR = File.realpath(File.expand_path('../../lib', __dir__))
  SPEC_DIR = File.expand_path('..', __dir__)

  TARGETS = %w[
    Hyperliquid::Info
    Hyperliquid::Exchange
    Hyperliquid::WS::Client
    Hyperliquid::Cloid
    Hyperliquid::Signing::Signer
    Hyperliquid::Signing::MultiSig
    Hyperliquid::SDK
    Hyperliquid::Client
  ].freeze

  # 'Const#method' or 'Const.method' => reason. Prefer adding a behavioural spec over an entry here.
  ALLOWLIST = {}.freeze

  module_function

  # True only when nothing narrowed the run: every spec file loaded, every loaded example selected,
  # no --only-failures / --dry-run, and the run was not aborted (e.g. --fail-fast).
  def full_suite_run?(config, world)
    return false if config.dry_run? || config.only_failures? || world.wants_to_quit || world.rspec_is_quitting

    # RSpec's default pattern, anchored at spec/ (`rake spec` passes it as a cwd-relative --pattern).
    all_files = Dir.glob(File.join(SPEC_DIR, '**{,/*/**}/*_spec.rb')).map { |f| File.expand_path(f) }.uniq.sort
    return false unless config.files_to_run.map { |f| File.expand_path(f) }.uniq.sort == all_files

    declared = world.example_groups.flat_map(&:descendants).sum { |group| group.examples.size }
    declared == world.example_count
  end

  # Returns [missing, unobserved]: methods with zero calls, and methods whose definition
  # Coverage never saw (the file was loaded before Coverage.start).
  def uncovered(coverage)
    missing = []
    unobserved = []
    target_methods.each do |label, method|
      file, line = method.source_location
      methods = coverage.dig(file, :methods)
      next unobserved << label unless methods

      counts = methods.select { |key, _| key[1] == method.original_name && key[2] == line }.values
      next unobserved << label if counts.empty?

      missing << label if counts.sum.zero?
    end
    [missing.sort, unobserved.sort]
  end

  # Public instance and singleton methods defined under lib/, excluding attribute
  # readers/writers (no bytecode, so Coverage cannot record them).
  def target_methods
    TARGETS.flat_map do |name|
      mod = Object.const_get(name)
      instance = mod.public_instance_methods(false).map { |m| ["#{name}##{m}", mod.instance_method(m)] }
      singleton = mod.singleton_class.public_instance_methods(false).map { |m| ["#{name}.#{m}", mod.method(m)] }
      (instance + singleton).select { |label, method| measurable?(label, method) }
    end
  end

  def measurable?(label, method)
    file, = method.source_location
    return false unless file && File.realpath(file).start_with?("#{LIB_DIR}/")
    return false if ALLOWLIST.key?(label)

    !RubyVM::InstructionSequence.of(method).nil?
  end

  def check!(coverage)
    missing, unobserved = uncovered(coverage)
    errors = []
    unless unobserved.empty?
      errors << "Method coverage could not observe #{unobserved.size} method(s); was lib/ loaded before " \
                "spec/support/method_coverage.rb started Coverage? #{unobserved.join(', ')}"
    end
    unless missing.empty?
      errors << "Public SDK methods never executed by the suite (add a behavioural spec):\n  " \
                "#{missing.join("\n  ")}"
    end
    raise errors.join("\n") unless errors.empty?
  end
end

RSpec.configure do |config|
  config.after(:suite) do
    coverage = Coverage.peek_result
    MethodCoverage.check!(coverage) if MethodCoverage.full_suite_run?(config, RSpec.world)
  end
end
