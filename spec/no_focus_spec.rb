# frozen_string_literal: true

require 'spec_helper'

# A committed focus filter (`fit`, `focus: true`, ...) makes `rspec` run only the focused examples
# and still exit 0, silently shrinking the suite. An example here would itself be filtered out by
# that focus, so the guard is a before(:suite) hook: any run that loads this file fails before
# the first example.
RSpec.configure do |config|
  config.before(:suite) do
    focus_pattern = /^\s*(?:RSpec\.)?(?:fit|fdescribe|fcontext|fspecify|fexample)\b|\bfocus:\s*true\b|,\s*:focus\b/
    this_file = File.expand_path(__FILE__)
    root = "#{File.dirname(__dir__)}/"

    offenders = Dir[File.expand_path('**/*.rb', __dir__)].flat_map do |file|
      next [] if file == this_file

      File.readlines(file).each_with_index.filter_map do |line, index|
        "#{file.delete_prefix(root)}:#{index + 1}: #{line.strip}" if line.match?(focus_pattern)
      end
    end

    raise "Focused specs found; remove the focus:\n#{offenders.join("\n")}" unless offenders.empty?
  end
end
