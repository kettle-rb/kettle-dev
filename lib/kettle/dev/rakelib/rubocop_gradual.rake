# frozen_string_literal: true

begin
  require "rubocop/gradual/rake_task"

  RuboCop::Gradual::RakeTask.new(:rubocop_gradual_debug) do |t|
    t.options = ["--debug"]
  end
rescue LoadError
  # simplecov:disable -- RuboCop Gradual is an optional development dependency.
  warn("[kettle-dev][rubocop_gradual.rake] failed to load rubocop/gradual/rake_task") if Kettle::Dev::DEBUGGING
  # simplecov:enable
end
