# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'prism'
require 'rbconfig'
require 'ripper'
require 'tmpdir'

# `rake verify:docs_only`: is every change vs HEAD (tracked and untracked) free of behaviour?
# Docs paths always qualify; a lib/ or scripts/ Ruby file tracked in HEAD qualifies only if its
# token stream (ignoring comments/whitespace/embdoc), magic comments, and __END__ data are unchanged.
module DocsOnlyCheck
  DOC_PATH = %r{\A(?:docs/|README\.md\z|CLAUDE\.md\z|example\.rb\z|spec/docs_coverage_spec\.rb\z)}
  CODE_PATH = %r{\A(?:lib|scripts)/.+\.rb\z}
  MAGIC = /\A\s*#\s*-?\*?-?\s*(?:frozen_string_literal|encoding|coding|shareable_constant_value|warn_indent)\b/i
  SKIPPED = %i[on_sp on_ignored_sp on_embdoc_beg on_embdoc on_embdoc_end].freeze
  NEWLINES = %i[on_nl on_ignored_nl on_comment].freeze

  module_function

  def first_offending_path
    changed_paths.find { |path| !docs_only?(path) }
  end

  # `git status --porcelain=v1 -z`: "XY path\0", and renames/copies add "\0orig_path".
  def changed_paths
    out = IO.popen(%w[git status --porcelain=v1 -uall -z], &:read)
    raise 'git status failed' unless Process.last_status.success?

    entries = out.split("\0")
    paths = []
    until entries.empty?
      entry = entries.shift
      paths << entry[3..]
      paths << entries.shift if entry[0].match?(/[RC]/)
    end
    paths
  end

  def docs_only?(path)
    return true if path.match?(DOC_PATH)
    return false unless path.match?(CODE_PATH) && File.file?(path)

    old = IO.popen(['git', 'show', "HEAD:#{path}"], err: File::NULL, &:read)
    return false unless Process.last_status.success?

    same_behaviour?(old, File.read(path))
  end

  def same_behaviour?(old, new)
    return false unless Prism.parse(new).success?

    signature(old) == signature(new)
  end

  def signature(src)
    [tokens(src), src.lines.grep(MAGIC), src.split(/^__END__$/, 2)[1]]
  end

  # A comment (and its newline) or a blank line is equivalent to one newline, so runs of
  # newline-ish tokens collapse to a single :nl marker.
  def tokens(src)
    stream = Ripper.lex(src).each_with_object([]) do |(_, event, tok, _), acc|
      next if SKIPPED.include?(event)

      if NEWLINES.include?(event)
        acc << :nl unless acc.empty? || acc.last == :nl
      else
        acc << [event, tok]
      end
    end
    stream.pop if stream.last == :nl
    stream
  end
end

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

# Explicit file paths bypass AllCops/Exclude (which keeps scripts/ out of the main task),
# so scripts get Lint + Security only. Do not add --force-exclusion.
RuboCop::RakeTask.new('rubocop:scripts') do |t|
  t.patterns = Dir['scripts/**/*.rb'] + %w[example.rb]
  t.options = %w[--only Lint,Security]
end
Rake::Task['rubocop:scripts'].clear_comments
Rake::Task['rubocop:scripts'].comment = 'Run RuboCop Lint and Security cops on scripts/ and example.rb'

desc 'Run specs, RuboCop, and the scripts Lint/Security check (what CI runs)'
task default: %i[spec rubocop rubocop:scripts]

desc 'Run the default task, then again on a clean clone of HEAD with a frozen lockfile'
task verify: %i[default verify:head]

namespace :verify do
  desc 'Run the default task in a clean clone of HEAD with BUNDLE_FROZEN=true (committed content only)'
  task :head do
    Dir.mktmpdir('hl-verify-head') do |dir|
      sh 'git', 'clone', '--quiet', '--local', '.', dir
      Bundler.with_unbundled_env do
        sh({ 'BUNDLE_FROZEN' => 'true' }, 'bundle', 'exec', 'rake', chdir: dir)
      end
    end
  end

  desc 'Exit 0 (DOCS_ONLY=yes) iff every change vs HEAD is docs-only; else exit 1 (DOCS_ONLY=no path=...)'
  task :docs_only do
    offending = DocsOnlyCheck.first_offending_path
    if offending
      puts "DOCS_ONLY=no path=#{offending}"
      exit 1
    end
    puts 'DOCS_ONLY=yes'
  end
end

desc 'Run the testnet integration gate (scripts/test_all.rb); exits 2 without HYPERLIQUID_PRIVATE_KEY'
task :integration do
  if ENV.fetch('HYPERLIQUID_PRIVATE_KEY', '').empty?
    warn 'rake integration: HYPERLIQUID_PRIVATE_KEY is not set; the testnet integration gate cannot run.'
    exit 2
  end
  _, status = Process.wait2(Process.spawn(RbConfig.ruby, '-rbundler/setup', 'scripts/test_all.rb'))
  exit(status.exitstatus || 1)
end

namespace :parity do
  desc 'Regenerate the Python-SDK parity fixtures into a tmpdir and diff them against spec/fixtures/parity'
  task :check do
    Dir.mktmpdir('hl-parity') do |dir|
      sh 'tools/parity/regenerate.sh', dir
      sh 'diff', '-r', 'spec/fixtures/parity', dir
    end
  end
end

# bundler/gem_tasks' `release` tags and pushes the tag before `gem push`; releases must push the gem first.
RELEASE_DISABLED = 'rake release is disabled; releases go through /hyperliquid-release: gem push first, tag after'
%w[release release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].clear
  desc "Disabled (#{name}): use /hyperliquid-release"
  task(name) { abort RELEASE_DISABLED }
end
