# frozen_string_literal: true

begin
  require "require_bench/tasks" if Kettle::Dev::REQUIRE_BENCH
rescue LoadError
  warn("[kettle-dev][require_bench.rake] failed to load require_bench/tasks") if Kettle::Dev::DEBUGGING
end
