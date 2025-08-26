# frozen_string_literal: true

# --- Appraisals (dev-only) ---
begin
  require "appraisal/task"

  desc("Update Appraisal gemfiles and run RuboCop Gradual autocorrect")
  task("appraisal:update") do
    bundle = Gem.bindir ? File.join(Gem.bindir, "bundle") : "bundle"

    run_in_unbundled = proc do
      env = {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"}

      # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle update --bundler
      ok = system(env, bundle, "update", "--bundler")
      abort("appraisal:update failed: bundle update --bundler under Appraisal.root.gemfile") unless ok

      # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle (install)
      ok = system(env, bundle)
      abort("appraisal:update failed: bundler install under Appraisal.root.gemfile") unless ok

      # 3) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal update
      ok = system(env, bundle, "exec", "appraisal", "update")
      abort("appraisal:update failed: bundle exec appraisal update") unless ok

      # 4) bundle exec rake rubocop_gradual:autocorrect
      ok = system(bundle, "exec", "rake", "rubocop_gradual:autocorrect")
      abort("appraisal:update failed: rubocop_gradual:autocorrect") unless ok
    end

    if defined?(Bundler)
      Bundler.with_unbundled_env(&run_in_unbundled)
    else
      run_in_unbundled.call
    end
  end
rescue LoadError
  warn("[kettle-dev][appraisal.rake] failed to load appraisal/tasks") if Kettle::Dev::DEBUGGING
end
