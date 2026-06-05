# frozen_string_literal: true

# --- Appraisals (dev-only) ---
begin
  require "appraisal/task"

  bundle = "bundle"
  appraisal_env = {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"}

  run_command = lambda do |failure_message, *args|
    ok = system(*args)
    raise(failure_message) unless ok
  end

  run_autocorrect = lambda do |task_name|
    run_command.call("#{task_name} failed: rubocop_gradual:autocorrect", bundle, "exec", "rake", "rubocop_gradual:autocorrect")
  end

  run_generate_steps = lambda do
    # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
    run_command.call(
      "appraisal:generate failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install",
      appraisal_env,
      bundle,
      "install"
    )

    # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal generate
    run_command.call(
      "appraisal:generate failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal generate",
      appraisal_env,
      bundle,
      "exec",
      "appraisal",
      "generate"
    )
  end

  run_appraisal_task = lambda do |task_name, primary_steps = nil|
    begin
      if primary_steps
        begin
          primary_steps.call
        rescue RuntimeError => e
          warn("[kettle-dev][#{task_name}] #{e.message}; falling back to appraisal:generate")
          run_generate_steps.call
        end
      else
        run_generate_steps.call
      end

      run_autocorrect.call(task_name)
    rescue RuntimeError => e
      abort(e.message)
    end
  end

  desc("Install Appraisal gemfiles (initial setup for projects that didn't previously use Appraisal)")
  task("appraisal:install") do
    run_in_unbundled = proc do
      run_appraisal_task.call(
        "appraisal:install",
        lambda do
          # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
          run_command.call(
            "appraisal:install failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install",
            appraisal_env,
            bundle,
            "install"
          )

          # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal install
          run_command.call(
            "appraisal:install failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal install",
            appraisal_env,
            bundle,
            "exec",
            "appraisal",
            "install"
          )
        end
      )
    end

    if defined?(Bundler)
      Bundler.with_unbundled_env(&run_in_unbundled)
    else
      run_in_unbundled.call
    end
  end

  desc("Generate Appraisal gemfiles without resolving appraisal locks")
  task("appraisal:generate") do
    run_in_unbundled = proc do
      run_appraisal_task.call("appraisal:generate")
    end

    if defined?(Bundler)
      Bundler.with_unbundled_env(&run_in_unbundled)
    else
      run_in_unbundled.call
    end
  end

  desc("Update Appraisal gemfiles and run RuboCop Gradual autocorrect")
  task("appraisal:update") do
    run_in_unbundled = proc do
      run_appraisal_task.call(
        "appraisal:update",
        lambda do
          # 1) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
          run_command.call(
            "appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install",
            appraisal_env,
            bundle,
            "install"
          )

          # 2) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle update --bundler
          run_command.call(
            "appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle update --bundler",
            appraisal_env,
            bundle,
            "update",
            "--bundler"
          )

          # 3) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install
          run_command.call(
            "appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle install",
            appraisal_env,
            bundle,
            "install"
          )

          # 4) BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal update
          run_command.call(
            "appraisal:update failed: BUNDLE_GEMFILE=Appraisal.root.gemfile bundle exec appraisal update",
            appraisal_env,
            bundle,
            "exec",
            "appraisal",
            "update"
          )
        end
      )
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
          rescue => e
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
