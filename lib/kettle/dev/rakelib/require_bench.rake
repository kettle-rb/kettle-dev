# frozen_string_literal: true

begin
  require "require_bench/tasks" if Kettle::Dev::REQUIRE_BENCH
rescue LoadError
  # simplecov:disable -- require_bench is an opt-in development dependency.
  warn("[kettle-dev][require_bench.rake] failed to load require_bench/tasks") if Kettle::Dev::DEBUGGING
  # simplecov:enable
end
