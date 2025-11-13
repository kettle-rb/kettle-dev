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

  # Delete all Appraisal lockfiles in gemfiles/ (*.gemfile.lock)
  desc("Delete Appraisal lockfiles (gemfiles/*.gemfile.lock)")
  task("appraisal:reset") do
    run_in_unbundled = proc do
      lock_glob = File.join("gemfiles", "*.gemfile.lock")
      locks = Dir.glob(lock_glob)

      if locks.empty?
        puts("[kettle-dev][appraisal:reset] no files matching #{lock_glob}")
      else
        failures = []
        locks.each do |f|
          begin
            File.delete(f)
          rescue Errno::ENOENT
            # Ignore if already gone
          rescue StandardError => e
            failures << [f, e]
          end
        end

        unless failures.empty?
          failed_list = failures.map { |(f, e)| "#{f} (#{e.class}: #{e.message})" }.join(", ")
          abort("appraisal:reset failed: unable to delete #{failed_list}")
        end

        puts("[kettle-dev][appraisal:reset] deleted #{locks.size} file(s)")
      end
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
