# frozen_string_literal: true

# Polls a condition set by another thread instead of sleeping a fixed time.
module WaitUntil
  # Returns the block's first truthy value; raises if it stays falsy for `timeout` seconds.
  def wait_until(timeout: 2, interval: 0.005, message: nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      result = yield
      return result if result

      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "wait_until timed out after #{timeout}s#{": #{message}" if message}"
      end
      sleep interval
    end
  end
end

RSpec.configure do |config|
  config.include WaitUntil
end
