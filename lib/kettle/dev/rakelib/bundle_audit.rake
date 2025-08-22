# Setup Bundle Audit
begin
  require "bundler/audit/task"

  Bundler::Audit::Task.new
  Kettle::Dev.register_default("bundle:audit:update")
  Kettle::Dev.register_default("bundle:audit")
rescue LoadError
  warn("[kettle-dev][bundle_audit.rake] failed to load bundle/audit/task") if Kettle::Dev::DEBUGGING
  desc("(stub) bundle:audit is unavailable")
  task("bundle:audit") do
    warn("NOTE: bundler-audit isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  desc("(stub) bundle:audit:update is unavailable")
  task("bundle:audit:update") do
    warn("NOTE: bundler-audit isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end
