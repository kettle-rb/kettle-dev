# frozen_string_literal: true

# --- Appraisals (dev-only) ---
begin
  require "appraisal/task"

  desc("Install Appraisal gemfiles (initial setup for projects that didn't previously use Appraisal)")
  task("appraisal:install") do
    bundle = "bundle"

    run_in_unbundled = proc do
      env = {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"}

      # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
      ok = system(env, bundle, "install")
      abort("appraisal:install failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install") unless ok

      # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal install
      ok = system(env, bundle, "exec", "appraisal", "install")
      abort("appraisal:install failed: bundle exec appraisal install") unless ok

      # 3) bundle exec rake rubocop_gradual:autocorrect
      ok = system(bundle, "exec", "rake", "rubocop_gradual:autocorrect")
      abort("appraisal:update failed: rubocop_gradual:autocorrect") unless ok
    end

    if defined?(Bundler)
      Bundler.with_unbundled_env(&run_in_unbundled)
    else
      run_in_unbundled.call
    end
  end

  desc("Update Appraisal gemfiles and run RuboCop Gradual autocorrect")
  task("appraisal:update") do
    bundle = "bundle"

    run_in_unbundled = proc do
      env = {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"}

      # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle update --bundler
      ok = system(env, bundle, "update", "--bundler")
      abort("appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle update --bundler") unless ok

      # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
      ok = system(env, bundle, "install")
      abort("appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install") unless ok

      # 3) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal update
      ok = system(env, bundle, "exec", "appraisal", "update")
      abort("appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal update") unless ok

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
