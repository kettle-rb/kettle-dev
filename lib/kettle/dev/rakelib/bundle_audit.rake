# frozen_string_literal: true

skip_bundle_audit = %w[1 true yes on].include?(ENV.fetch("KETTLE_DEV_SKIP_BUNDLE_AUDIT", "").downcase)

define_bundle_audit_stub_tasks = lambda do |description_prefix, warning|
  desc("#{description_prefix} bundle:audit")
  task("bundle:audit") do
    warn(warning.call("bundle:audit"))
  end
  desc("#{description_prefix} bundle:audit:update")
  task("bundle:audit:update") do
    warn(warning.call("bundle:audit:update"))
  end
end

if skip_bundle_audit
  define_bundle_audit_stub_tasks.call(
    "(skipped)",
    ->(task_name) { "NOTE: #{task_name} skipped because KETTLE_DEV_SKIP_BUNDLE_AUDIT is enabled" }
  )
else
  # Setup Bundle Audit
  begin
    require "bundler/audit/task"

    Bundler::Audit::Task.new
    Kettle::Dev.register_default("bundle:audit:update")
    Kettle::Dev.register_default("bundle:audit")
  rescue LoadError
    warn("[kettle-dev][bundle_audit.rake] failed to load bundle/audit/task") if Kettle::Dev::DEBUGGING
    define_bundle_audit_stub_tasks.call(
      "(stub)",
      ->(_task_name) { "NOTE: bundler-audit isn't installed, or is disabled for #{RUBY_VERSION} in the current environment" }
    )
  end
end
