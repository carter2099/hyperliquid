#!/usr/bin/env ruby
# frozen_string_literal: true

# Hyperliquid Ruby SDK - testnet integration gate.
#
# Runs every scripts/test_NN_*.rb (sorted) in its default, automated-safe mode,
# each in its own process group under the locked bundle (-rbundler/setup).
#
#   - Pre-flight: `testnet_wallet_check.rb --assert`; on failure nothing runs.
#   - Post-flight: the same assert after the last script; a violation is a leak.
#   - Per-script status from the exit code: 0 PASS, 1 FAIL, 75 INCONCLUSIVE,
#     77 SKIPPED, 78 GUARDED, anything else FAIL; TIMEOUT when killed.
#   - Output is streamed with the private key redacted (and ANSI stripped when
#     stdout is not a TTY). The last stdout line is always
#       INTEGRATION GATE: PASS|FAIL total=N pass=a guarded=b skipped=c inconclusive=d fail=e timeout=f not_run=g
#     optionally followed by the reasons `precondition`, `leak`, `strict`.
#   - JSON summary: $HL_GATE_SUMMARY (default tmp/integration-summary.json).
#
# Environment:
#   HYPERLIQUID_PRIVATE_KEY  testnet agent key (required)
#   HL_SCRIPT_TIMEOUT        per-script seconds (default 300): TERM, 5 s grace, KILL
#   HL_GATE_BUDGET           whole-gate seconds (default 2400); later scripts are NOT_RUN
#   HL_GATE_STRICT=1         also fail on any SKIPPED/INCONCLUSIVE/GUARDED script
#
# Opt-in destructive/locking modes are CLI args on individual scripts, never run here:
#   ruby -rbundler/setup scripts/test_10_vault.rb deposit|withdraw
#   ruby -rbundler/setup scripts/test_12_staking.rb delegate|undelegate
#   ruby -rbundler/setup scripts/test_16_send_to_evm_with_data.rb live
#   ruby -rbundler/setup scripts/test_17_create_vault.rb live
#
# Usage:
#   rake integration
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_all.rb

require 'fileutils'
require 'json'
require 'rbconfig'
require 'time'

# 'test_NN_name.rb' => 'reason' for scripts deliberately excluded from the gate.
OPT_OUT = {}.freeze

SCRIPTS_DIR = __dir__
ROOT = File.expand_path('..', SCRIPTS_DIR)
LOCK_PATH = File.join(ROOT, 'tmp', 'integration.lock')
SUMMARY_PATH = ENV['HL_GATE_SUMMARY'] ? File.expand_path(ENV['HL_GATE_SUMMARY'])
                                      : File.join(ROOT, 'tmp', 'integration-summary.json')
WALLET_ASSERT = [File.join(SCRIPTS_DIR, 'testnet_wallet_check.rb'), '--assert'].freeze

TTY = $stdout.tty?
COLOR = TTY && ENV['NO_COLOR'].nil?
KILL_GRACE = 5
DRAIN_GRACE = 2
STRICT = ENV['HL_GATE_STRICT'] == '1'

STATUS_BY_EXIT = { 0 => 'PASS', 1 => 'FAIL', 75 => 'INCONCLUSIVE', 77 => 'SKIPPED', 78 => 'GUARDED' }.freeze
COUNT_KEYS = %w[PASS GUARDED SKIPPED INCONCLUSIVE FAIL TIMEOUT NOT_RUN].freeze
RESULT_LINE = /^RESULT (?:PASS|FAIL|INCONCLUSIVE|SKIPPED|GUARDED) .*/
ANSI = /\e\[[0-9;?]*[ -\/]*[@-~]/

$stdout.sync = true

def positive_seconds(name, default)
  value = ENV[name]
  return default if value.nil? || value.empty?

  seconds = Float(value, exception: false)
  abort "#{name} must be a positive number of seconds, got #{value.inspect}" unless seconds&.positive?
  seconds
end

SCRIPT_TIMEOUT = positive_seconds('HL_SCRIPT_TIMEOUT', 300)
GATE_BUDGET = positive_seconds('HL_GATE_BUDGET', 2400)

def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

def paint(text, code) = COLOR ? "\e[#{code}m#{text}\e[0m" : text

# Rewrites child output before it reaches our stdout: redacts the private key
# (with or without 0x, any case), strips ANSI and collapses \r redraws when not a
# TTY. Works line by line; a partial line is only flushed when the child goes
# quiet, holding back any tail that could be the start of the key.
class OutputFilter
  attr_reader :result_line

  def initialize(io, secret_hex)
    @io = io
    @buffer = +''.b
    @hex = secret_hex
    @secret = secret_hex && Regexp.new("(?:0x)?#{Regexp.escape(secret_hex)}", Regexp::IGNORECASE)
    @result_line = nil
  end

  def <<(chunk)
    @buffer << chunk.b
    while (newline = @buffer.index("\n"))
      emit(@buffer.slice!(0..newline))
    end
    flush_partial(final: false) if @buffer.bytesize > 65_536
  end

  def flush_partial(final:)
    return if @buffer.empty?

    keep = final ? 0 : held_tail_length
    emit(@buffer.slice!(0, @buffer.bytesize - keep))
  end

  private

  def emit(text)
    return if text.empty?

    text = text.gsub(@secret, '[REDACTED]') if @secret
    plain = text.gsub(ANSI, '')
    unless TTY
      plain = plain.split("\n", -1).map { |l| l.split("\r").reject(&:empty?).last || '' }.join("\n")
      text = plain
    end
    plain.each_line { |l| @result_line = l.strip if l.match?(RESULT_LINE) }
    @io.write(text)
  end

  # Bytes at the end of the buffer that could begin the key or an escape sequence.
  def held_tail_length
    tail = 0
    if @hex
      candidates = ["0x#{@hex}", @hex]
      max = [@buffer.bytesize, candidates.first.bytesize - 1].min
      max.downto(1) do |n|
        piece = @buffer.byteslice(-n, n).downcase
        if candidates.any? { |c| c.downcase.start_with?(piece) }
          tail = n
          break
        end
      end
    end
    escape = @buffer.rindex("\e")
    tail = [tail, @buffer.bytesize - escape].max if escape && @buffer.bytesize - escape < 16 &&
                                                    !@buffer.byteslice(escape..).match?(ANSI)
    tail
  end
end

def secret_hex
  hex = ENV['HYPERLIQUID_PRIVATE_KEY'].to_s.strip.sub(/\A0x/i, '')
  hex.length >= 8 ? hex.b : nil
end

def signal_group(pid, signal)
  Process.kill(signal, -pid)
rescue Errno::ESRCH, Errno::EPERM
  nil
end

# Runs one child under the locked bundle in its own process group, streaming its
# merged stdout/stderr through OutputFilter. The deadline is enforced inside the
# read loop, so a silent or pipe-hogging child cannot hang the gate.
# Returns { status_code:, timed_out:, seconds:, result_line: }.
def run_child(args, deadline)
  started = now
  reader, writer = IO.pipe
  filter = OutputFilter.new($stdout, secret_hex)
  pid = Process.spawn(RbConfig.ruby, '-rbundler/setup', *args,
                      chdir: ROOT, pgroup: true, in: File::NULL, out: writer, err: writer)
  writer.close

  status = nil
  timed_out = false
  term_sent_at = nil
  exited_at = nil
  eof = false

  until eof && status
    if status.nil?
      _, status = Process.wait2(pid, Process::WNOHANG)
      exited_at = now if status
    end

    if status.nil? && (term_sent_at.nil? ? now >= deadline : now >= term_sent_at + KILL_GRACE)
      if term_sent_at.nil?
        timed_out = true
        term_sent_at = now
        signal_group(pid, 'TERM')
      else
        signal_group(pid, 'KILL')
      end
    end

    if eof
      sleep 0.1 # pipe closed; waiting for the process to exit (or be killed)
    else
      ready = IO.select([reader], nil, nil, 0.5)
      if ready
        begin
          filter << reader.read_nonblock(65_536)
        rescue IO::WaitReadable
          nil
        rescue EOFError
          eof = true
        end
      else
        filter.flush_partial(final: false)
      end
    end

    # The child is gone but something it spawned still holds the pipe open.
    next unless status && !eof && now >= exited_at + DRAIN_GRACE

    signal_group(pid, 'KILL')
    eof = true
  end
  filter.flush_partial(final: true)

  { status_code: timed_out ? nil : status.exitstatus, timed_out: timed_out,
    seconds: (now - started).round(1), result_line: filter.result_line }
ensure
  reader&.close
  if pid && status.nil?
    signal_group(pid, 'KILL')
    begin
      Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end
  end
end

def run_wallet_assert(label)
  puts
  puts "#{label}: ruby -rbundler/setup scripts/testnet_wallet_check.rb --assert"
  run = run_child(WALLET_ASSERT, now + SCRIPT_TIMEOUT)
  status = if run[:timed_out] then 'TIMEOUT'
           elsif run[:status_code]&.zero? then 'PASS'
           else 'FAIL'
           end
  { status: status, exit_code: run[:status_code], seconds: run[:seconds] }
end

def final_line(counts, total, reasons, pass)
  line = "INTEGRATION GATE: #{pass ? 'PASS' : 'FAIL'} total=#{total} " +
         COUNT_KEYS.map { |k| "#{k.downcase}=#{counts[k]}" }.join(' ')
  reasons.empty? ? line : "#{line} #{reasons.join(' ')}"
end

def write_summary(summary)
  FileUtils.mkdir_p(File.dirname(SUMMARY_PATH))
  tmp = "#{SUMMARY_PATH}.#{Process.pid}.tmp"
  File.write(tmp, "#{JSON.pretty_generate(summary)}\n")
  File.rename(tmp, SUMMARY_PATH)
end

if ENV['HYPERLIQUID_PRIVATE_KEY'].to_s.strip.empty?
  puts 'Error: set HYPERLIQUID_PRIVATE_KEY (testnet agent key).'
  puts 'Usage: HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_all.rb'
  exit 1
end

FileUtils.mkdir_p(File.dirname(LOCK_PATH))
lock = File.open(LOCK_PATH, File::RDWR | File::CREAT, 0o644)
unless lock.flock(File::LOCK_EX | File::LOCK_NB)
  puts "Another integration run holds #{LOCK_PATH}; exiting."
  exit 1
end

started_at = Time.now.utc
gate_deadline = now + GATE_BUDGET
all_scripts = Dir[File.join(SCRIPTS_DIR, 'test_[0-9][0-9]_*.rb')].map { |p| File.basename(p) }.sort
scripts = all_scripts.reject { |name| OPT_OUT.key?(name) }

puts "Integration gate: #{scripts.length} script(s), timeout #{SCRIPT_TIMEOUT.to_i}s each, " \
     "budget #{GATE_BUDGET.to_i}s#{STRICT ? ', strict' : ''}"
unless OPT_OUT.empty?
  puts 'Opted out:'
  OPT_OUT.each { |name, reason| puts "  #{name}: #{reason}" }
end

results = []
reasons = []
preflight = run_wallet_assert('Pre-flight')
postflight = nil

if preflight[:status] == 'PASS'
  scripts.each do |name|
    if now >= gate_deadline
      results << { name: name, status: 'NOT_RUN', exit_code: nil, seconds: 0, result_line: nil }
      next
    end

    puts
    puts '#' * 60
    puts "# Running: #{name}"
    puts '#' * 60
    run = run_child([File.join(SCRIPTS_DIR, name)], [now + SCRIPT_TIMEOUT, gate_deadline].min)
    status = run[:timed_out] ? 'TIMEOUT' : STATUS_BY_EXIT.fetch(run[:status_code], 'FAIL')
    results << { name: name, status: status, exit_code: run[:status_code], seconds: run[:seconds],
                 result_line: run[:result_line] }
    puts paint(">>> #{name}: #{status} (exit #{run[:status_code].inspect}, #{run[:seconds]}s)",
               status == 'PASS' ? 32 : 31)
  end

  postflight = run_wallet_assert('Post-flight')
  reasons << 'leak' unless postflight[:status] == 'PASS'
else
  reasons << 'precondition'
  results = scripts.map { |name| { name: name, status: 'NOT_RUN', exit_code: nil, seconds: 0, result_line: nil } }
end

counts = COUNT_KEYS.to_h { |k| [k, results.count { |r| r[:status] == k }] }
soft = counts['SKIPPED'] + counts['INCONCLUSIVE'] + counts['GUARDED']
reasons << 'strict' if STRICT && soft.positive?
pass = (counts['FAIL'] + counts['TIMEOUT'] + counts['NOT_RUN']).zero? && reasons.empty?

write_summary(
  gate: pass ? 'PASS' : 'FAIL',
  started_at: started_at.iso8601,
  finished_at: Time.now.utc.iso8601,
  preflight: preflight,
  postflight: postflight,
  scripts: results
)

puts
puts '=' * 60
puts 'INTEGRATION SUMMARY'
puts '=' * 60
results.each do |r|
  line = format('%-14s %-40s %s', "[#{r[:status]}]", r[:name], r[:result_line] || '')
  puts paint(line.rstrip, r[:status] == 'PASS' ? 32 : 31)
end
puts "Pre-flight: #{preflight[:status]}   Post-flight: #{postflight ? postflight[:status] : 'NOT_RUN'}"
puts "Summary: #{SUMMARY_PATH}"
puts final_line(counts, results.length, reasons, pass)
exit(pass ? 0 : 1)
