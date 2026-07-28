# frozen_string_literal: true

# External stdlib
require "digest"
require "open3"
require "shellwords"
require "time"
require "fileutils"
require "net/http"
require "json"
require "uri"
require "yaml"
require "set"

# External gems
require "kettle/ndjson"
require "kettle/rb/compat_matrix"
require "ruby-progressbar"

require_relative "interactive_release_command"
require_relative "lockfile_reset"
require_relative "release_secrets"

module Kettle
  module Dev
    class ReleaseCLI
      QUIET_ENV = {
        "KETTLE_JEM_QUIET" => "true",
        "KETTLE_JEM_DEBUG" => "false",
        "KETTLE_DEV_DEBUG" => "false",
        "STRUCTUREDMERGE_DEBUG" => "false",
        "DEBUG" => nil,
        "BUNDLE_QUIET" => "true",
        "BUNDLE_DEBUG" => "false",
        "BUNDLER_DEBUG" => "false",
        "BUNDLE_VERBOSE" => "false",
        "DEBUG_RESOLVER" => nil,
        "DEBUG_RESOLVER_TREE" => nil,
        "BUNDLER_DEBUG_RESOLVER" => nil,
        "BUNDLER_DEBUG_RESOLVER_TREE" => nil,
        "DEBUG_COMPACT_INDEX" => nil,
        "MOLINILLO_DEBUG" => nil,
        "BUNDLE_SILENCE_DEPRECATIONS" => "true",
        "BUNDLE_SILENCE_ROOT_WARNING" => "true",
        "BUNDLE_SUPPRESS_INSTALL_USING_MESSAGES" => "true"
      }.freeze
      DEBUG_TRUE_VALUES = %w[1 true yes on].freeze
      RELEASE_VALIDATION_SOURCE = "https://gem.coop"

      class << self
        def run_cmd!(cmd)
          # For Bundler-invoked build/release, explicitly prefix SKIP_GEM_SIGNING so
          # the signing step is skipped even when Bundler scrubs ENV.
          # Always do this on CI to avoid interactive prompts; locally only when explicitly requested.
          if ENV["SKIP_GEM_SIGNING"] && /\Abundle(\s+exec)?\s+rake\s+(build|release)\b/.match?(cmd)
            cmd = "SKIP_GEM_SIGNING=true #{cmd}"
          end
          puts "$ #{cmd}"
          # Pass a plain Hash for the environment to satisfy tests and avoid ENV object oddities
          env_hash = command_env

          # Some commands are interactive (e.g., `bundle exec rake release` prompting for RubyGems MFA).
          # Using capture3 detaches STDIN, preventing prompts from working. For such commands, use system
          # so they inherit the current TTY and can read the user's input.
          interactive = /\Abundle(\s+exec)?\s+rake\s+release\b/.match?(cmd) ||
            /\Agem\s+push\b/.match?(cmd) ||
            /\A(bundle\s+exec\s+)?kettle-changelog\b/.match?(cmd)
          if interactive
            ok = system(env_hash, cmd)
            unless ok
              exit_code = $?.respond_to?(:exitstatus) ? $?.exitstatus : 1
              abort("Command failed: #{cmd} (exit #{exit_code})")
            end
            return
          end

          # Non-interactive: capture output so we can surface clear diagnostics on failure
          stdout_str, stderr_str, status = Open3.capture3(env_hash, cmd)

          # Echo command output to match prior behavior
          $stdout.print(stdout_str) unless stdout_str.nil? || stdout_str.empty?
          $stderr.print(stderr_str) unless stderr_str.nil? || stderr_str.empty?

          unless status.success?
            exit_code = status.exitstatus
            # Keep the original prefix to avoid breaking any tooling/tests that grep for it,
            # but add the exit status and a brief diagnostic tail from stderr.
            diag = ""
            unless stderr_str.to_s.empty?
              tail = stderr_str.lines.last(20).join
              diag = "\n--- STDERR (last 20 lines) ---\n#{tail}".rstrip
            end
            abort("Command failed: #{cmd} (exit #{exit_code})#{diag}")
          end
        end

        private

        def command_env
          env_hash = ENV.respond_to?(:to_hash) ? ENV.to_hash : ENV.to_h
          return env_hash if debug_env_enabled?

          env_hash.merge(QUIET_ENV)
        end

        def debug_env_enabled?
          DEBUG_TRUE_VALUES.include?(ENV.fetch("KETTLE_DEV_DEBUG", "").downcase)
        end
      end

      private

      def abort(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      end

      public

      def initialize(start_step: 0, local_ci: false, version: nil, appraisal_task: nil, skip_steps: nil, skip_bundle_audit: nil, ci_workflows: nil, skip_remotes: nil, secrets_provider_name: nil, yes: false, **options)
        @root = Kettle::Dev::CIHelpers.project_root
        @git = Kettle::Dev::GitAdapter.new(@root)
        @start_step = (start_step || 0).to_i
        @start_step = 0 if @start_step < 0
        @skip_steps = normalize_skip_steps(skip_steps)
        @ci_workflows = normalize_ci_workflows(ci_workflows || ENV["K_RELEASE_CI_WORKFLOWS"])
        @skip_remotes = normalize_skip_remotes(skip_remotes || ENV["K_RELEASE_SKIP_REMOTES"])
        @local_ci = !!local_ci
        @skip_bundle_audit = truthy_value?(skip_bundle_audit) || truthy_value?(ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"])
        @yes = !!yes
        @version_override = Kettle::Dev::Versioning.normalize_explicit_version(version)
        @appraisal_task = normalize_appraisal_task(appraisal_task || ENV["KETTLE_RELEASE_APPRAISAL_TASK"])
        @release_candidate = nil
        @event_stream = options[:event_stream]
        @event_recorder = Kettle::Ndjson.event_recorder(@event_stream, phase_timings: [])
        @secrets_provider = options[:secrets_provider] || Kettle::Dev::ReleaseSecrets::Factory.build(provider_name: secrets_provider_name)
        @report_path = options[:report_path]
        @json_output = !!options[:json_output]
        @json_io = options[:json_io] || $stdout
        @command_events = []
        @diagnostics = []
        @started_at = nil
        @finished_report = nil
        @changelog_generated_coverage = false
      end

      def run
        @started_at = monotonic_time
        emit_run_start
        status = "ok"
        error = nil
        with_bundle_audit_skip_env do
          with_machine_stdout_redirect do
            run_with_release_environment
          end
        end
      rescue SystemExit => e
        status = e.status.to_i.zero? ? "ok" : "failed"
        error = e
        record_diagnostic("release_exit", e.message, severity: (status == "ok") ? "info" : "error", blocking: status != "ok")
        raise
      rescue => e
        status = "failed"
        error = e
        record_diagnostic("release_error", "#{e.class}: #{e.message}", severity: "error", blocking: true)
        raise
      ensure
        finish_release_report(status: status, error: error)
      end

      attr_reader :finished_report

      def run_with_release_environment
        run_pre_release_checks! if run_step?(0)

        # 1. Ensure Bundler version ✓
        ensure_bundler_2_7_plus! if run_step?(1)

        version = nil
        committed = nil
        trunk = nil
        feature = nil
        branch_stack_release = false

        # 2. Version detection and sanity checks + prompt
        if run_step?(2)
          version = detect_version
          puts "Detected version: #{version.inspect}"

          latest_overall = nil
          latest_for_series = nil
          begin
            gem_name = detect_gem_name
            latest_overall, latest_for_series = latest_released_versions(gem_name, version)
          rescue => e
            warn("[kettle-release] RubyGems.org release check failed: #{e.class}: #{e.message}")
            warn(e.backtrace.first(3).map { |l| "  " + l }.join("\n")) if ENV["KETTLE_DEV_DEBUG"]
            warn("Proceeding without RubyGems.org latest version info.")
          end

          if latest_overall
            msg = "Latest released: #{latest_overall}"
            if latest_for_series && latest_for_series != latest_overall
              msg += " | Latest for series #{Gem::Version.new(version).segments[0, 2].join(".")}.x: #{latest_for_series}"
            elsif latest_for_series
              msg += " (matches current series)"
            end
            puts msg

            cur = Gem::Version.new(version)
            overall = Gem::Version.new(latest_overall)
            cur_series = cur.segments[0, 2]
            overall_series = overall.segments[0, 2]
            # Ensure latest_for_series actually matches our current series; ignore otherwise.
            if latest_for_series
              lfs_series = Gem::Version.new(latest_for_series).segments[0, 2]
              latest_for_series = nil unless lfs_series == cur_series
            end
            # Determine the sanity-check target correctly for the current series.
            # If RubyGems.org has a newer overall series than our current series, only compare
            # against the latest published in our current series. If that cannot be determined
            # (e.g., offline), skip the sanity check rather than treating the overall as target.
            target = if (cur_series <=> overall_series) == -1
              latest_for_series
            else
              latest_overall
            end
            # IMPORTANT: Never treat a higher different-series "latest_overall" as a downgrade target.
            # If our current series is behind overall and RubyGems.org does not report a latest_for_series,
            # then we cannot determine the correct target for this series and should skip the check.
            if (cur_series <=> overall_series) == -1 && target.nil?
              puts "Could not determine latest released version from RubyGems.org (offline?). Proceeding without sanity check."
            elsif target
              bump = Kettle::Dev::Versioning.classify_bump(target, version)
              case bump
              when :same
                series = cur_series.join(".")
                warn("version.rb (#{version}) matches the latest released version for series #{series} (#{target}).")
                abort("Aborting: version bump required. Bump PATCH/MINOR/MAJOR/EPIC.")
              when :downgrade
                series = cur_series.join(".")
                warn("version.rb (#{version}) is lower than the latest released version for series #{series} (#{target}).")
                abort("Aborting: version must be bumped above #{target}.")
              else
                label = {epic: "EPIC", major: "MAJOR", minor: "MINOR", patch: "PATCH"}[bump] || bump.to_s.upcase
                puts "Proposed bump type: #{label} (from #{target} -> #{version})"
              end
            else
              puts "Could not determine latest released version from RubyGems.org (offline?). Proceeding without sanity check."
            end
          else
            puts "Could not determine latest released version from RubyGems.org (offline?). Proceeding without sanity check."
          end

          confirm_yes!("Have you updated lib/**/version.rb and CHANGELOG.md for v#{version}? [y/N]", "> ", "Aborted: please update version.rb and CHANGELOG.md, then re-run.")

          # Initial validation: Ensure README.md and LICENSE.txt have identical sets of copyright years; also ensure current year present when matched
          validate_copyright_years!

          # Ensure README KLOC badge reflects current CHANGELOG coverage denominator
          begin
            update_readme_kloc_badge!
          rescue => e
            warn("Failed to update KLOC badge in README: #{e.class}: #{e.message}")
          end

          # Update Rakefile.example header banner with current version and date
          begin
            update_rakefile_example_header!(version)
          rescue => e
            warn("Failed to update Rakefile.example header: #{e.class}: #{e.message}")
          end
        end

        prepare_rubocop_lts_local_branch! if rubocop_lts_release_preflight_needed?
        prepare_release_lockfiles_for_release_tasks! if release_lockfile_preflight_needed?

        # 3. bin/setup
        run_cmd!("bin/setup") if run_step?(3)
        # 4. bin/rake
        run_cmd!(release_default_task_command) if run_step?(4)

        # 5. appraisal:generate (optional) + canonical docs build
        if run_step?(5)
          appraisals_path = File.join(@root, "Appraisals")
          if File.file?(appraisals_path)
            puts "Appraisals detected at #{Kettle::Dev.display_path(appraisals_path)}. Running: bin/rake #{@appraisal_task}"
            run_cmd!("bin/rake #{@appraisal_task}")
          else
            puts "No Appraisals file found; skipping #{@appraisal_task}"
          end

          puts "Generating docs site via canonical task: bin/rake yard"
          run_cmd!("bin/rake yard")
        end

        # 6. git user + commit release prep
        if run_step?(6)
          prepare_release_lockfiles_for_commit!
          ensure_git_user!
          version ||= detect_version
          committed = commit_release_prep!(version)
        end

        # 7. optional local CI via act
        maybe_run_local_ci_before_push!(committed, force: local_ci?) if run_step?(7)

        # 8. ensure trunk synced
        if run_step?(8) && !local_ci?
          trunk = detect_trunk_branch
          feature = current_branch
          branch_stack_release = branch_stack_release_branch?(feature, trunk)
          if branch_stack_release
            puts "Kettle-family branch stack release branch detected: #{feature}; skipping trunk sync/rebase."
          end
          puts "Trunk branch detected: #{trunk}"
          ensure_trunk_synced_before_push!(trunk, feature) unless branch_stack_release
        elsif run_step?(8)
          puts "Local CI release mode: skipping remote trunk sync before publishing."
        end

        # 9. push branches
        if run_step?(9) && !local_ci?
          validate_release_lockfiles!(stage: "before push")
          push!
        end

        # 10. monitor CI after push
        if run_step?(10) && !local_ci?
          validate_release_lockfiles!(stage: "before CI monitoring")
          monitor_workflows_after_push!
        end

        # 11. merge feature into trunk and push
        if run_step?(11) && !local_ci?
          trunk ||= detect_trunk_branch
          feature ||= current_branch
          branch_stack_release ||= branch_stack_release_branch?(feature, trunk)
          if branch_stack_release
            puts "Kettle-family branch stack release branch detected: #{feature}; skipping merge into #{trunk}."
          else
            merge_feature_into_trunk_and_push!(trunk, feature)
          end
        end

        # 12. checkout trunk and pull
        if run_step?(12) && !local_ci?
          trunk ||= detect_trunk_branch
          feature ||= current_branch
          branch_stack_release ||= branch_stack_release_branch?(feature, trunk)
          if branch_stack_release
            puts "Kettle-family branch stack release branch detected: #{feature}; staying on release branch."
          else
            checkout!(trunk)
            pull!(trunk)
          end
        end

        # 13. signing guidance and checks
        if run_step?(13)
          if signing_enabled?
            puts "TIP: For local dry-runs or testing the release workflow, set SKIP_GEM_SIGNING=true to avoid PEM password prompts."
            if @yes
              puts "Proceeding with signing enabled because --yes was provided."
            elsif Kettle::Dev::InputAdapter.tty?
              # In CI, avoid interactive prompts when no TTY is present (e.g., act or GitHub Actions "CI validation").
              # Non-interactive CI runs should not abort here; later signing checks are either stubbed in tests
              # or will be handled explicitly by ensure_signing_setup_or_skip!.
              print("Proceed with signing enabled? This may hang waiting for a PEM password. [y/N]: ")
              ans = Kettle::Dev::InputAdapter.gets&.strip
              unless ans&.downcase&.start_with?("y")
                abort("Aborted. Re-run with SKIP_GEM_SIGNING=true bundle exec kettle-release (or set it in your environment).")
              end
            else
              warn("Non-interactive shell detected (non-TTY); skipping interactive signing confirmation.")
            end
          end

          ensure_signing_setup_or_skip!
          ensure_release_secrets_ready_for_signing! if signing_enabled? && release_secrets_configured?
        end

        # 14. build
        if run_step?(14)
          ensure_release_secrets_ready_for_signing! if signing_enabled? && release_secrets_configured?
          if signing_enabled? && release_secrets_configured?
            puts "Running build with gem signing passphrase from configured secrets provider (#{release_secrets_provider_label})..."
          else
            puts "Running build (you may be prompted for the signing key password)..."
          end
          run_cmd!("bundle exec rake build")
        end

        # 15. release and tag
        if run_step?(15)
          version ||= detect_version
          gem_name = detect_gem_name
          @release_candidate = build_release_candidate(gem_name, version)
          if local_ci?
            with_unpublished_candidate_cleanup { release_gem_and_tag_locally!(version) }
          else
            ensure_release_secrets_ready_for_signing! if signing_enabled? && release_secrets_configured?
            if release_secrets_configured?
              puts "Running release with configured secrets provider (#{release_secrets_provider_label}) for signing and RubyGems MFA prompts..."
            else
              puts "Running release (you may be prompted for signing key password and RubyGems MFA OTP)..."
            end
            with_unpublished_candidate_cleanup do
              run_cmd!("bundle exec rake release")
              @release_candidate.published = true
              confirm_release_candidate_available!(@release_candidate)
            end
            mark_rubygems_release_cache_bust(version)
          end
        end

        # 16. generate checksums
        #    Checksums are generated after release to avoid including checksums/ in gem package
        #    Rationale: Running gem_checksums before release may commit checksums/ and cause Bundler's
        #    release build to include them in the gem, thus altering the artifact, and invalidating the checksums.
        if run_step?(16)
          # Generate checksums for the just-built artifact, commit them, then validate
          version ||= detect_version
          gem_path = checksum_gem_path_for_version!(version)
          run_cmd!("bin/gem_checksums #{Shellwords.escape(gem_path)}")
          validate_checksums!(version, stage: "after release")
        end

        # 17. push checksum commit (gem_checksums already commits)
        if run_step?(17)
          push!
          push_tags! if local_ci?
        end

        # 18. create GitHub release (optional)
        if run_step?(18)
          version ||= detect_version
          maybe_create_github_release!(version)
        end

        # 19. push tags to remotes (final step)
        push_tags! if run_step?(19) && !local_ci?

        # Final success message
        begin
          version ||= detect_version
          gem_name = detect_gem_name
          human_output.puts "\n🚀 Release #{gem_name} v#{version} Complete 🚀"
        rescue => e
          Kettle::Dev.debug_error(e, __method__)
          # Fallback if detection fails for any reason
          human_output.puts "\n🚀 Release v#{version || "unknown"} Complete 🚀"
        end
      end

      def normalize_appraisal_task(value)
        task = value.to_s.strip
        return "appraisal:generate" if task.empty?
        return "appraisal:generate" if task == "generate" || task == "appraisal:generate"
        return "appraisal:update" if task == "update" || task == "appraisal:update"

        abort("Unsupported appraisal task #{value.inspect}; use appraisal:generate or appraisal:update.")
      end

      def normalize_skip_steps(value)
        raw_steps = Array(value).flat_map { |part| part.to_s.split(",") }.map(&:strip).reject(&:empty?)
        raw_steps.map do |raw|
          abort("Invalid skip_steps value #{raw.inspect}; use comma-separated release step numbers from 0 to 19.") unless raw.match?(/\A\d+\z/)

          step = raw.to_i
          abort("Invalid skip_steps value #{raw.inspect}; release steps are numbered 0 to 19.") unless step.between?(0, 19)

          step
        end.uniq
      end

      def normalize_ci_workflows(value)
        workflows = Array(value).flat_map { |part| part.to_s.split(",") }.map(&:strip).reject(&:empty?)
        workflows.map { |workflow| workflow.match?(/\.ya?ml\z/) ? workflow : "#{workflow}.yml" }.uniq
      end

      def normalize_skip_remotes(value)
        remotes = Array(value).flat_map { |part| part.to_s.split(",") }.map(&:strip).reject(&:empty?)
        invalid = remotes.find { |remote| !remote.match?(/\A[A-Za-z0-9_.-]+\z/) }
        abort("Invalid skip remotes value #{invalid.inspect}; use comma-separated git remote names.") if invalid

        remotes.uniq
      end

      private

      def local_ci?
        @local_ci
      end

      def skip_bundle_audit?
        @skip_bundle_audit
      end

      def truthy_value?(value)
        return true if value == true

        DEBUG_TRUE_VALUES.include?(value.to_s.downcase)
      end

      def run_step?(step)
        @start_step <= step && !@skip_steps.include?(step)
      end

      def rubocop_lts_release_preflight_needed?
        (3..5).any? { |step| run_step?(step) }
      end

      def release_lockfile_preflight_needed?
        (3..5).any? { |step| run_step?(step) }
      end

      def prepare_rubocop_lts_local_branch!
        local_root = rubocop_lts_local_root
        return unless local_root

        ruby_gem = selected_rubocop_lts_ruby_gem
        return unless ruby_gem

        branch = Kettle::Rb::CompatMatrix.rubocop_lts_branch_for_gem(ruby_gem)
        abort("Cannot select RUBOCOP_LTS_LOCAL branch for #{ruby_gem.inspect}.") unless branch

        checkout = File.join(local_root, "rubocop-lts")
        return if active_local_branch_stack_release_checkout?(checkout)

        current, ok = git_output(["-C", checkout, "branch", "--show-current"])
        abort("Cannot inspect RUBOCOP_LTS_LOCAL checkout at #{checkout}.") unless ok
        return if current == branch

        puts "Switching RUBOCOP_LTS_LOCAL checkout #{checkout} to #{branch} for #{ruby_gem}."
        _stdout, switched = git_output(["-C", checkout, "switch", branch])
        abort("Cannot switch RUBOCOP_LTS_LOCAL checkout at #{checkout} to #{branch}. Commit or stash local changes, then retry.") unless switched
      end

      def active_local_branch_stack_release_checkout?(checkout)
        return false if local_kettle_family_release_target_branches.empty?

        same_path?(@root, checkout)
      end

      def same_path?(left, right)
        File.realpath(left) == File.realpath(right)
      rescue Errno::ENOENT
        false
      end

      def rubocop_lts_local_root
        value = ENV["RUBOCOP_LTS_LOCAL"].to_s.strip
        return nil if value.empty? || %w[false 0 no off].include?(value.downcase)
        return File.join(Dir.home, "src", "rubocop-lts") if %w[true 1 yes on].include?(value.downcase)
        return value if value.start_with?("/")

        File.join(Dir.home, value)
      end

      def selected_rubocop_lts_ruby_gem
        path = File.join(@root, "gemfiles", "modular", "style_local.gemfile")
        return nil unless File.file?(path)

        content = File.read(path)
        # This reads the generated kettle-jem style_local.gemfile declaration
        # without evaluating the Gemfile during release preflight.
        local_gems = content[/\blocal_gems\s*=\s*%w\[(.*?)\]/m, 1].to_s.split
        local_gems.find { |gem_name| Kettle::Rb::CompatMatrix.rubocop_ruby_gem?(gem_name) }
      end

      def run_pre_release_checks!
        puts "Running pre-release checks via kettle-pre-release..."
        Kettle::Dev::PreReleaseCLI.new(check_num: 1).run
        run_changelog!
      end

      def prepare_release_lockfiles_for_commit!
        reset_release_lockfiles!(stage: "before release prep commit") unless @release_lockfiles_reset_for_release_tasks
        validate_release_lockfiles!(stage: "before release prep commit")
      end

      def prepare_release_lockfiles_for_release_tasks!
        reset_release_lockfiles!(stage: "before release task bundle installs")
      end

      def reset_release_lockfiles!(stage:)
        return if @release_lockfiles_reset_for_release_tasks && stage == "before release task bundle installs"

        attempts = release_lockfile_reset_attempts(stage)
        attempts.times do |index|
          attempt = index + 1
          puts "Resetting release lockfiles with local path dependencies disabled #{stage} (attempt #{attempt}/#{attempts})..."
          begin
            lockfile_reset.reset(Kettle::Dev::LockfileReset::RELEASE_LOCKFILES_TARGET)
            break
          rescue Kettle::Dev::Error => error
            raise unless error.message.start_with?("Reset #{Kettle::Dev::LockfileReset::RELEASE_LOCKFILES_TARGET} failed validation:")

            # Keep release-facing failures shaped like the lockfile validation
            # guard, even when the shared reset helper is the component that
            # detects the unrepaired lockfile.
            break
          rescue => error
            raise unless retryable_release_lockfile_reset_error?(error) && attempt < attempts

            puts "Release lockfile reset could not resolve a gem from #{RELEASE_VALIDATION_SOURCE}; waiting before retry #{attempt + 1}/#{attempts}."
            sleep(release_availability_probe_interval)
          end
        end

        diagnostics = release_lockfile_paths.flat_map { |path| release_lockfile_diagnostics(path) }
        if diagnostics.empty?
          puts "Release lockfile reset complete: #{release_lockfile_paths.length} lockfile(s) checked, no diagnostics remain."
        end
        @release_lockfiles_reset_for_release_tasks = true if stage == "before release task bundle installs"
      end

      def release_lockfile_reset_attempts(stage)
        stage == "before release task bundle installs" ? release_availability_probe_attempts : 1
      end

      def retryable_release_lockfile_reset_error?(error)
        message = error.message.to_s
        message.include?("Bundler::GemNotFound") ||
          message.include?("Could not find gem") ||
          message.include?("can no longer be found in that source")
      end

      def validate_release_lockfiles!(stage:)
        diagnostics = release_lockfile_paths.flat_map { |path| release_lockfile_diagnostics(path) }
        return if diagnostics.empty?
        if stage == "before push"
          diagnostics = reset_release_lockfiles_before_push(diagnostics)
          return if diagnostics.empty?
        end

        abort(<<~MSG)
          Release lockfile validation failed #{stage}:
          #{diagnostics.map { |diagnostic| "  - #{diagnostic}" }.join("\n")}
          Re-run bundle lock/update with local path development env disabled before releasing.
        MSG
      end

      def release_lockfile_paths
        lockfile_reset.lockfile_paths
      end

      def release_lockfile_normalization_needed?(path)
        lockfile_reset.normalization_needed?(path)
      end

      def normalize_release_lockfile!(path)
        lockfile_reset.reset_lockfile!(path)
      end

      def release_gemfile_for_lockfile(path)
        lockfile_reset.gemfile_for_lockfile(path)
      end

      def release_lockfile_normalization_env
        lockfile_reset.normalization_env
      end

      def release_lockfile_diagnostics(path)
        lockfile_reset.diagnostics(path)
      end

      def release_lockfile_has_local_path_remote?(path)
        lockfile_reset.has_local_path_remote?(path)
      end

      def release_lockfile_local_path_remote_lines(path)
        lockfile_reset.local_path_remote_lines(path)
      end

      def release_lockfile_empty_registry_checksums(path)
        lockfile_reset.empty_registry_checksums(path)
      end

      def release_lockfile_has_any_sha_checksum?(path)
        lockfile_reset.has_any_sha_checksum?(path)
      end

      def release_lockfile_path_source_gems(path)
        lockfile_reset.path_source_gems(path)
      end

      def release_lockfile_path_dependency_gems(path)
        lockfile_reset.path_dependency_gems(path)
      end

      def release_lockfile_label(path)
        Kettle::Dev.display_path(path)
      end

      def reset_release_lockfiles_before_push(diagnostics)
        puts "Release lockfile validation found #{diagnostics.length} issue(s) before push:"
        diagnostics.each { |diagnostic| puts "  - #{diagnostic}" }
        puts "Running one fallback release lockfile reset before push; tracked lockfile changes will amend the release prep commit."
        changed_before_reset = changed_release_lockfile_paths
        begin
          lockfile_reset.reset(Kettle::Dev::LockfileReset::RELEASE_LOCKFILES_TARGET)
        rescue Kettle::Dev::Error => error
          puts error.message
        end

        remaining = release_lockfile_paths.flat_map { |path| release_lockfile_diagnostics(path) }
        if remaining.empty?
          amend_release_lockfile_reset_commit(changed_before_reset)
          return []
        end

        puts "Release lockfile reset did not repair all before-push issues:"
        remaining.each { |diagnostic| puts "  - #{diagnostic}" }
        remaining
      end

      def amend_release_lockfile_reset_commit(changed_before_reset = [])
        paths = changed_release_lockfile_paths
        if paths.empty?
          if changed_before_reset.empty?
            puts "Fallback release lockfile reset result: diagnostics cleared, but tracked lockfiles matched the release prep commit before and after reset; no amend is possible."
          else
            puts "Fallback release lockfile reset result: diagnostics cleared by restoring tracked lockfiles to the release prep commit; no amend is needed."
          end
          return
        end

        puts "Fallback release lockfile reset result: diagnostics cleared; amending release prep commit with #{paths.length} lockfile(s)."
        abort("Failed to stage reset release lockfiles.") unless @git.add_paths(paths)
        abort("Failed to amend release prep commit with reset lockfiles.") unless @git.commit_amend_no_edit
      end

      def changed_release_lockfile_paths
        release_lockfile_paths.select { |path| git_path_changed?(path) }
      end

      def git_path_changed?(path)
        if @git.respond_to?(:diff_head_quiet?)
          !@git.diff_head_quiet?(path)
        else
          !@git.diff_quiet?(path)
        end
      end

      def lockfile_reset
        @lockfile_reset ||= Kettle::Dev::LockfileReset.new(root: @root, command_runner: method(:run_cmd!))
      end

      def run_changelog!
        cmd = "bundle exec kettle-changelog"
        cmd = "#{cmd} --version #{Shellwords.escape(@version_override)}" if @version_override
        cmd = "#{cmd} --yes" if @yes
        run_cmd!(cmd)
        @changelog_generated_coverage = true
      end

      def release_default_task_command
        # `kettle-changelog` generates strict coverage by running `bundle exec kettle-test`.
        # When that happened during this same release invocation, the default task can skip
        # its test/coverage prerequisites and still run lint, audit, documentation, and any
        # other non-test release checks. Resumed releases do not set this flag, so they keep
        # the full default task behavior.
        return "KETTLE_DEV_SKIP_TESTS=true bin/rake" if @changelog_generated_coverage

        "bin/rake"
      end

      def confirm_yes!(message, prompt, abort_message)
        puts(message)
        if @yes
          puts("#{prompt}y")
          return
        end

        print(prompt)
        ans = Kettle::Dev::InputAdapter.gets&.strip
        abort(abort_message) unless ans&.downcase&.start_with?("y")
      end

      def changelog_strict?
        ENV.fetch("K_CHANGELOG_STRICT", "true").downcase != "false"
      end

      def changelog_coverage_hard?
        ENV.fetch("K_CHANGELOG_COVERAGE_HARD", "true").downcase != "false"
      end

      # Update the README KLOC badge number based on the denominator in the current version's COVERAGE line in CHANGELOG.md.
      # - Parses the current version section of CHANGELOG.md
      # - Finds a line matching: "- COVERAGE: ... -- <tested>/<total> lines ..."
      # - Computes KLOC = total / 1000.0
      # - Formats with three decimals (e.g., 0.076, 2.175, 10.123)
      # - Rewrites the [🧮kloc-img] badge line in README.md (and README.md.example when present)
      #   replacing only the numeric portion after "KLOC-" while preserving other URL params.
      def update_readme_kloc_badge!
        version = detect_version
        # Extract only the current version's section
        section, _compare_ref, _tag_ref = extract_changelog_for_version(version)
        return unless section

        # Example match: "- COVERAGE: 97.70% -- 2125/2175 lines in 20 files"
        m = section.lines.find { |l| /-\s*COVERAGE:\s*.+--\s*\d+\/(\d+)\s+lines/i.match?(l) }
        return unless m

        denom = m.match(/-\s*COVERAGE:\s*.+--\s*\d+\/(\d+)\s+lines/i)[1].to_i
        kloc = denom.to_f / 1000.0
        kloc_str = format("%.3f", kloc)

        update_badge_number_in_file(File.join(@root, "README.md"), kloc_str)
        example_path = File.join(@root, "README.md.example")
        update_badge_number_in_file(example_path, kloc_str) if File.file?(example_path)
      end

      # Helper to update the [🧮kloc-img] badge in the given file path.
      # Replaces only the numeric portion after "KLOC-" keeping other URL parts intact.
      def update_badge_number_in_file(path, kloc_str)
        return unless File.file?(path)

        content = File.read(path)
        # Match the specific reference line, capture groups around the number
        # Example: [🧮kloc-img]: https://img.shields.io/badge/KLOC-2.175-FFDD67.svg?style=...
        new_content = content.gsub(/(\[🧮kloc-img\]:\s*https?:\/\/img\.shields\.io\/badge\/KLOC-)(\d+(?:\.\d+)?)(-[^\s]*)/, "\\1#{kloc_str}\\3")
        if new_content != content
          File.write(path, new_content)
        end
      end

      # Update Rakefile.example banner to include current gem version and current date.
      # Looks for a line starting with "# kettle-dev Rakefile v" and replaces version/date.
      def update_rakefile_example_header!(version)
        path = File.join(@root, "Rakefile.example")
        return unless File.file?(path)

        content = File.read(path)
        today = Time.now.strftime("%Y-%m-%d")
        new_line = "# kettle-dev Rakefile v#{version} - #{today}"
        new_content = content.gsub(/^# kettle-dev Rakefile v.*$/, new_line)
        if new_content != content
          File.write(path, new_content)
        end
      end

      # Validate that README.md and CHANGELOG.md contain identical sets of copyright years.
      # This helps ensure docs are kept in sync when bumping the years.
      # Aborts with a helpful message when they differ.
      def validate_copyright_years!
        readme = File.join(@root, "README.md")
        license = File.join(@root, "LICENSE.txt")
        unless File.file?(readme) && File.file?(license)
          # If either file is missing, skip this check silently (some projects might not have both initially)
          return
        end

        # Normalize year formatting in both files before comparing
        reformat_copyright_year_lines!(readme)
        reformat_copyright_year_lines!(license)

        r_years = extract_years_from_file(readme)
        l_years = extract_years_from_file(license)
        if r_years == l_years
          # If they match, ensure the current year is present; if not, inject it into both files.
          current_year = Time.now.year
          unless r_years.include?(current_year)
            # Update both files by appending current year to the set and rewriting the lines canonically
            updated_years = r_years.dup
            updated_years << current_year
            # Write back to both files using canonical collapse formatting
            inject_years_into_file!(readme, updated_years)
            inject_years_into_file!(license, updated_years)
          end
          return
        end

        abort(<<~MSG)
          Mismatched copyright years between README.md and LICENSE.txt.
            README.md:   #{r_years.to_a.sort.join(", ")}
            LICENSE.txt: #{l_years.to_a.sort.join(", ")}
          Please update both files so they contain the identical set of years.
        MSG
      end

      # Extract a Set of Integer years from the given file.
      # It searches for lines containing the word "Copyright" (case-insensitive),
      # then parses four-digit years and year ranges like "2012-2015" (hyphen or en dash).
      # Returns Set[Integer].
      def extract_years_from_file(path)
        years = Set.new
        content = File.read(path)
        # Only consider lines that look like copyright notices to reduce false positives
        content.each_line do |line|
          next unless /copyright/i.match?(line)

          # Expand ranges first (supports hyphen-minus and en dash)
          line.scan(/\b(19\d{2}|20\d{2})\s*[-–]\s*(19\d{2}|20\d{2})\b/).each do |a, b|
            s = a.to_i
            e = b.to_i
            if e < s
              s, e = e, s
            end
            (s..e).each { |y| years << y }
          end

          # Then single standalone years
          line.scan(/\b(19\d{2}|20\d{2})\b/).each do |y|
            years << y[0].to_i
          end
        end
        years
      end

      # Collapse a set/array of years into a canonical, comma-separated string, combining
      # consecutive runs into ranges with a hyphen (YYYY-YYYY) and leaving gaps as commas.
      def collapse_years(enum)
        arr = enum.to_a.map(&:to_i).uniq.sort
        return "" if arr.empty?

        segments = []
        start = arr.first
        prev = start
        arr[1..-1].to_a.each do |y|
          if y == prev + 1
            prev = y
            next
          else
            segments << ((start == prev) ? start.to_s : "#{start}-#{prev}")
            start = prev = y
          end
        end
        segments << ((start == prev) ? start.to_s : "#{start}-#{prev}")
        segments.join(", ")
      end

      # Inject the provided set of years into copyright lines, rewriting them in canonical form.
      # - Finds lines containing 'copyright' (case-insensitive) and a years blob.
      # - Replaces that blob with the canonical collapsed form of the union of existing years and given years.
      # - If multiple copyright lines, updates each consistently.
      def inject_years_into_file!(path, years_set)
        content = File.read(path)
        changed = false
        canonical_all = collapse_years(years_set)
        new_lines = content.each_line.map do |line|
          unless /copyright/i.match?(line)
            next line
          end

          m = line.match(/\A(?<pre>.*?copyright[^0-9]*)(?<years>(?:\b(?:19|20)\d{2}\b(?:\s*[-–]\s*\b(?:19|20)\d{2}\b)?)(?:\s*,\s*\b(?:19|20)\d{2}\b(?:\s*[-–]\s*\b(?:19|20)\d{2}\b)?)*)(?<post>.*)\z/i)
          unless m
            next line
          end

          new_line = "#{m[:pre]}#{canonical_all}#{m[:post]}"
          changed ||= (new_line != line)
          new_line
        end
        if changed
          File.write(path, new_lines.join)
        end
      end

      # Rewrite copyright lines in-place to collapse years into canonical ranges.
      # Only modifies lines that contain the word "copyright" (case-insensitive).
      def reformat_copyright_year_lines!(path)
        content = File.read(path)
        changed = false
        new_lines = content.each_line.map do |line|
          unless /copyright/i.match?(line)
            next line
          end

          # Capture three parts: prefix up to first year, the year blob, and the rest
          m = line.match(/\A(?<pre>.*?copyright[^0-9]*)(?<years>(?:\b(?:19|20)\d{2}\b(?:\s*[-–]\s*\b(?:19|20)\d{2}\b)?)(?:\s*,\s*\b(?:19|20)\d{2}\b(?:\s*[-–]\s*\b(?:19|20)\d{2}\b)?)*)(?<post>.*)\z/i)
          unless m
            # No parsable year sequence on this line; leave as-is
            next line
          end

          years_blob = m[:years]
          # Reuse extraction logic on just the years blob
          years = []
          years_blob.scan(/\b(19\d{2}|20\d{2})\s*[-–]\s*(19\d{2}|20\d{2})\b/).each do |a, b|
            s = a.to_i
            e = b.to_i
            s, e = e, s if e < s
            (s..e).each { |y| years << y }
          end
          years_blob.scan(/\b(19\d{2}|20\d{2})\b/).each { |y| years << y[0].to_i }
          canonical = collapse_years(years)
          new_line = "#{m[:pre]}#{canonical}#{m[:post]}"
          changed ||= (new_line != line)
          new_line
        end
        if changed
          File.write(path, new_lines.join)
        end
      end

      def monitor_workflows_after_push!
        ensure_github_pull_request_for_ci!
        # Use abort-on-failure CI monitor to match historical behavior and specs
        Kettle::Dev::CIMonitor.monitor_all!(restart_hint: "bundle exec kettle-release start_step=10", workflows: @ci_workflows)
      end

      def ensure_github_pull_request_for_ci!
        branch = current_branch
        return if branch.to_s.empty?

        trunk = detect_trunk_branch
        return if branch == trunk

        gh_remote = preferred_github_remote
        return unless gh_remote

        owner, repo = parse_github_owner_repo(remote_url(gh_remote))
        return unless owner && repo

        pull_request = github_pull_request_for_branch(owner: owner, repo: repo, branch: branch, base: trunk)
        if pull_request
          puts "GitHub pull request ##{pull_request.fetch("number")} already open for #{branch} -> #{trunk}: #{pull_request.fetch("url")}"
          return
        end

        create_github_pull_request!(owner: owner, repo: repo, branch: branch, base: trunk)
      end

      def github_pull_request_for_branch(owner:, repo:, branch:, base:)
        output = gh_output!(
          "pr",
          "list",
          "--repo",
          "#{owner}/#{repo}",
          "--head",
          branch,
          "--base",
          base,
          "--state",
          "open",
          "--json",
          "number,url",
          "--limit",
          "1"
        )
        Array(JSON.parse(output)).first
      rescue JSON::ParserError => e
        Kettle::Dev.debug_error(e, __method__)
        abort("Could not parse GitHub pull request list from gh CLI.")
      end

      def create_github_pull_request!(owner:, repo:, branch:, base:)
        output = gh_output!(
          "pr",
          "create",
          "--repo",
          "#{owner}/#{repo}",
          "--head",
          branch,
          "--base",
          base,
          "--title",
          "Release #{branch}",
          "--body",
          "Automated release validation PR for `#{branch}`.\n\nThis PR lets GitHub Actions run before kettle-release merges the branch into `#{base}`."
        )
        puts "Created GitHub pull request for #{branch} -> #{base}: #{output.strip}"
      end

      def gh_output!(*args)
        stdout_str, stderr_str, status = Open3.capture3(self.class.send(:command_env), "gh", *args)
        return stdout_str if status.success?

        exit_code = status.respond_to?(:exitstatus) ? status.exitstatus : 1
        diag = stderr_str.to_s.empty? ? "" : "\n--- STDERR ---\n#{stderr_str}".rstrip
        abort("GitHub pull request setup failed: gh #{args.join(" ")} (exit #{exit_code})#{diag}")
      rescue Errno::ENOENT
        abort("GitHub pull request setup failed: gh CLI is required to create or find the release PR.")
      end

      def run_cmd!(cmd)
        cmd = bundle_audit_skip_command(cmd)
        emit_command_event(cmd, "started")
        with_bundle_audit_skip_env do
          with_machine_stdout_redirect do
            run_command_with_release_secrets!(cmd)
          end
        end
        emit_command_event(cmd, "ok")
      rescue SystemExit => e
        emit_command_event(cmd, "failed", reason: e.message)
        raise
      rescue => e
        emit_command_event(cmd, "failed", reason: "#{e.class}: #{e.message}")
        raise
      end

      def bundle_audit_skip_command(cmd)
        return cmd unless skip_bundle_audit?
        return cmd unless /(?:\A|\s)bin\/rake\b/.match?(cmd)
        return cmd if cmd.start_with?("KETTLE_DEV_SKIP_BUNDLE_AUDIT=")

        "KETTLE_DEV_SKIP_BUNDLE_AUDIT=true #{cmd}"
      end

      def run_command_with_release_secrets!(cmd)
        return self.class.run_cmd!(cmd) unless release_secret_command?(cmd) && release_secrets_configured?

        puts "$ #{cmd}"
        _stdout_str, stderr_str, status = Kettle::Dev::InteractiveReleaseCommand.new(secrets_provider: @secrets_provider).call(
          self.class.send(:command_env),
          cmd
        )
        return if status.success?

        exit_code = status.respond_to?(:exitstatus) ? status.exitstatus : 1
        diag = stderr_str.to_s.empty? ? "" : "\n--- STDERR (last 20 lines) ---\n#{stderr_str.lines.last(20).join}".rstrip
        abort("Command failed: #{cmd} (exit #{exit_code})#{diag}")
      rescue Kettle::Dev::Error => error
        abort(error.message)
      end

      def release_secrets_configured?
        !@secrets_provider.instance_of?(Kettle::Dev::ReleaseSecrets::Provider)
      end

      def release_secrets_provider_label
        release_secrets_configured? ? @secrets_provider.class.name.to_s.split("::").last : "interactive"
      end

      def signing_enabled?
        ENV.fetch("SKIP_GEM_SIGNING", "false").casecmp("false").zero?
      end

      def ensure_release_secrets_ready_for_signing!
        value = @secrets_provider.gem_signing_passphrase.to_s
        abort(release_secrets_configuration_message("gem signing passphrase was empty")) if value.empty?
      rescue Kettle::Dev::Error => error
        abort(release_secrets_configuration_message(error.message))
      end

      def release_secrets_configuration_message(reason)
        <<~MSG.strip
          Release secrets provider was requested, but #{reason}.
          Configure the 1Password CLI before release:
            KETTLE_RELEASE_1PASSWORD_ITEM=Rubygems
            KETTLE_RELEASE_1PASSWORD_GEM_SIGNING_PASSPHRASE_FIELD=GEM-SIGN-PASSPHRASE
          Or provide an explicit reference:
            KETTLE_RELEASE_1PASSWORD_GEM_SIGNING_PASSPHRASE_REFERENCE=op://<vault>/<item>/<field>
          If `op` is installed outside PATH:
            KETTLE_RELEASE_1PASSWORD_CLI=/absolute/path/to/op
          Ensure `op` is installed and signed in. Secret prompts are not allowed when --secrets-provider is set.
        MSG
      end

      def release_secret_command?(cmd)
        /\Abundle(\s+exec)?\s+rake\s+(build|release)\b/.match?(cmd) ||
          /\Agem\s+push\b/.match?(cmd)
      end

      def with_bundle_audit_skip_env
        return yield unless skip_bundle_audit?

        previous = ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"]
        ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"] = "true"
        yield
      ensure
        if skip_bundle_audit?
          previous.nil? ? ENV.delete("KETTLE_DEV_SKIP_BUNDLE_AUDIT") : ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"] = previous
        end
      end

      def git_output(args)
        # Route all git interactions through the GitAdapter so tests can safely mock them
        out, ok = @git.capture(args)
        [out.to_s.strip, !!ok]
      end

      def ensure_git_user!
        name, ok1 = git_output(%w[config user.name])
        email, ok2 = git_output(%w[config user.email])
        abort("Git user.name or user.email not configured.") unless ok1 && ok2 && !name.empty? && !email.empty?
      end

      def ensure_bundler_2_7_plus!
        begin
          require "bundler"
        rescue LoadError => e
          Kettle::Dev.debug_error(e, __method__)
          abort("Bundler is required. Please install bundler >= 2.7.0 and try again.")
        end
        ver = Gem::Version.new(Bundler::VERSION)
        min = Gem::Version.new("2.7.0")
        if ver < min
          abort("kettle-release requires Bundler >= 2.7.0 for reproducible builds by default. Current: #{Bundler::VERSION}. Please upgrade bundler.")
        end
      end

      def maybe_run_local_ci_before_push!(committed, force: false)
        mode = (ENV["K_RELEASE_LOCAL_CI"] || "").strip.downcase
        run_it =
          if force
            true
          else
            case mode
            when "true", "1", "yes", "y" then true
            when "ask"
              print("Run local CI with 'act' before pushing? [Y/n] ")
              ans = Kettle::Dev::InputAdapter.gets&.strip
              ans.nil? || ans.empty? || /\Ay(es)?\z/i.match?(ans)
            else
              false
            end
          end
        return unless run_it

        act_ok = begin
          system("act", "--version", out: File::NULL, err: File::NULL)
        rescue => e
          Kettle::Dev.debug_error(e, __method__)
          false
        end
        unless act_ok
          msg = "Local CI requires 'act'. Install https://github.com/nektos/act to enable."
          abort(msg) if force
          puts "Skipping local CI: 'act' command not found. Install https://github.com/nektos/act to enable."
          return
        end

        root = Kettle::Dev::CIHelpers.project_root
        workflows_dir = File.join(root, ".github", "workflows")
        candidates = Kettle::Dev::CIHelpers.workflows_list(root)

        chosen = (ENV["K_RELEASE_LOCAL_CI_WORKFLOW"] || "").strip
        if !chosen.empty?
          chosen = "#{chosen}.yml" unless /\.ya?ml\z/.match?(chosen)
        else
          chosen = if candidates.include?("locked_deps.yml")
            "locked_deps.yml"
          elsif candidates.include?("locked_deps.yaml")
            "locked_deps.yaml"
          else
            candidates.first
          end
        end

        unless chosen
          msg = "Local CI requires at least one workflow under .github/workflows."
          abort(msg) if force
          puts "Skipping local CI: no workflows found under .github/workflows."
          return
        end

        file_path = File.join(workflows_dir, chosen)
        unless File.file?(file_path)
          msg = "Local CI selected workflow not found: #{Kettle::Dev.display_path(file_path)}"
          abort(msg) if force
          puts "Skipping local CI: selected workflow not found: #{Kettle::Dev.display_path(file_path)}"
          return
        end

        puts "== Running local CI with act on #{chosen} =="
        ok = system("act", "-W", file_path)
        if ok
          puts "Local CI succeeded for #{chosen}."
        else
          puts "Local CI failed for #{chosen}."
          if committed
            puts "Rolling back release prep commit (soft reset)..."
            @git.reset_soft("HEAD^")
          end
          abort("Aborting due to local CI failure.")
        end
      end

      def release_gem_and_tag_locally!(version)
        tag = "v#{version}"
        gem_path = gem_file_for_version(version)
        unless gem_path && File.file?(gem_path)
          abort("Unable to locate built gem for version #{version} in pkg/. Did the build succeed?")
        end

        _out, tag_exists = git_output(["rev-parse", "-q", "--verify", "refs/tags/#{tag}"])
        if tag_exists
          puts "Local tag #{tag} already exists."
        else
          puts "Creating local git tag #{tag} without pushing it."
          abort("Failed to create local tag #{tag}.") unless @git.tag_annotated(tag, tag)
        end

        puts "Publishing #{File.basename(gem_path)} to RubyGems without pushing git refs..."
        run_cmd!("gem push #{Shellwords.escape(gem_path)}")
        gem_name = gem_name_from_gem_path(gem_path, version)
        @release_candidate ||= build_release_candidate(gem_name, version)
        @release_candidate.published = true
        confirm_release_candidate_available!(@release_candidate)
        mark_rubygems_release_cache_bust(version, gem_name: gem_name)
      end

      def build_release_candidate(gem_name, version)
        ReleaseCandidate.new(
          gem_name: gem_name.to_s,
          version: version.to_s,
          installed_before: gem_version_installed?(gem_name, version),
          published: false
        )
      end

      def with_unpublished_candidate_cleanup
        yield
      rescue SystemExit, StandardError
        cleanup_unpublished_release_candidate(@release_candidate)
        raise
      end

      def cleanup_unpublished_release_candidate(candidate)
        return unless candidate
        return if candidate.published
        return if candidate.installed_before
        return unless gem_version_installed?(candidate.gem_name, candidate.version)

        warn(
          "Release of #{candidate.gem_name} #{candidate.version} was not validated; " \
          "uninstalling the local candidate gem so future bundle updates cannot resolve an unreleased version."
        )
        uninstall_release_candidate(candidate)
      end

      def uninstall_release_candidate(candidate)
        run_cmd!(
          "gem uninstall #{Shellwords.escape(candidate.gem_name)} " \
          "-v #{Shellwords.escape(candidate.version)} -x -I --ignore-dependencies"
        )
      rescue SystemExit, StandardError => error
        warn("Could not uninstall local candidate #{candidate.gem_name} #{candidate.version}: #{error.message}")
        warn("Manual cleanup: gem uninstall #{candidate.gem_name} -v #{candidate.version} -x -I --ignore-dependencies")
      end

      def gem_version_installed?(gem_name, version)
        Gem::Specification.reset
        Gem::Specification.find_all_by_name(gem_name.to_s, "= #{version}").any?
      rescue Gem::LoadError
        false
      end

      def confirm_release_candidate_available!(candidate)
        run_release_availability_probe(candidate)
        candidate.published = true
        true
      rescue SystemExit
        raise
      rescue => error
        abort(<<~MSG)
          Published gem availability could not be validated for #{candidate.gem_name} #{candidate.version}: #{error.class}: #{error.message}
          kettle-release will clean up any local candidate install that was introduced by this failed release attempt.
          If the push actually succeeded, resolve the registry/checksum state manually before resuming.
        MSG
      end

      def run_release_availability_probe(candidate)
        script_path = write_release_availability_probe(candidate)
        attempts = release_availability_probe_attempts
        last_stderr = nil
        last_status = nil
        sleep(release_availability_probe_initial_delay)
        attempts.times do |index|
          attempt = index + 1
          puts("Validating #{candidate.gem_name} #{candidate.version} from #{RELEASE_VALIDATION_SOURCE} (attempt #{attempt}/#{attempts})")
          stdout_str = nil
          stderr_str = nil
          status = nil
          with_unbundled_release_probe_env do
            stdout_str, stderr_str, status = Open3.capture3(self.class.send(:command_env), Gem.ruby, script_path)
          end
          $stdout.print(stdout_str) unless stdout_str.to_s.empty?
          return true if status.success?

          last_stderr = stderr_str
          last_status = status
          sleep(release_availability_probe_interval) if attempt < attempts
        end

        diag = last_stderr.to_s.empty? ? "" : "\n--- STDERR ---\n#{last_stderr}".rstrip
        abort("Published gem availability probe failed for #{candidate.gem_name} #{candidate.version} after #{attempts} attempt(s) (exit #{last_status.exitstatus})#{diag}")
      ensure
        FileUtils.rm_f(script_path) if script_path
      end

      def release_availability_probe_attempts
        15
      end

      def release_availability_probe_initial_delay
        5
      end

      def release_availability_probe_interval
        10
      end

      def with_unbundled_release_probe_env(&block)
        if defined?(Bundler)
          Bundler.with_unbundled_env(&block)
        else
          yield
        end
      end

      def write_release_availability_probe(candidate)
        dir = File.join(@root, "tmp", "kettle-release")
        FileUtils.mkdir_p(dir)
        path = File.join(dir, "validate-#{candidate.gem_name}-#{candidate.version}-#{$$}.rb")
        File.write(path, release_availability_probe_script(candidate))
        path
      end

      def release_availability_probe_script(candidate)
        GemSourceProbe.bundler_inline_script(
          name: candidate.gem_name,
          version: candidate.version,
          source_url: RELEASE_VALIDATION_SOURCE
        )
      end

      def detect_version
        Kettle::Dev::Versioning.detect_version(@root, override: @version_override)
      end

      def detect_gem_name
        gemspecs = Dir[File.join(@root, "*.gemspec")]
        abort("Could not find a .gemspec in project root.") if gemspecs.empty?
        path = gemspecs.min
        content = File.read(path)
        m = content.match(/spec\.name\s*=\s*(["'])([^"']+)\1/)
        abort("Could not determine gem name from #{Kettle::Dev.display_path(path)}.") unless m
        m[2]
      end

      def latest_released_versions(gem_name, current_version)
        data = Kettle::Dev::RubyGemsVersions.fetch(gem_name, version_hint: current_version)
        return [nil, nil] unless data.is_a?(Array)

        versions = data.map { |h| h["number"] }.compact
        versions.reject! { |v| v.to_s.include?("-pre") || v.to_s.include?(".pre") || /[a-zA-Z]/.match?(v.to_s) }
        gversions = versions.map { |s| Gem::Version.new(s) }.sort
        latest_overall = gversions.last&.to_s

        cur = Gem::Version.new(current_version)
        series = cur.segments[0, 2]
        series_versions = gversions.select { |gv| gv.segments[0, 2] == series }
        latest_series = series_versions.last&.to_s
        [latest_overall, latest_series]
      rescue => e
        Kettle::Dev.debug_error(e, __method__)
        [nil, nil]
      end

      def mark_rubygems_release_cache_bust(version, gem_name: nil)
        gem_name ||= detect_gem_name
        Kettle::Dev::RubyGemsVersions.mark_released(gem_name, version)
      rescue => error
        warn("[kettle-release] could not mark RubyGems.org cache-bust for release-state: #{error.class}: #{error.message}") if Kettle::Dev::DEBUGGING
      end

      def gem_name_from_gem_path(gem_path, version)
        basename = File.basename(gem_path, ".gem")
        basename.delete_suffix("-#{version}")
      end

      def commit_release_prep!(version)
        msg = "🔖 Prepare release v#{version}"
        # Stage all changes (including new/untracked files) prior to committing
        abort("Failed to stage release prep changes.") unless @git.add_all
        out, _ = git_output(["status", "--porcelain"])
        if out.empty?
          puts "No changes to commit for release prep (continuing)."
          false
        else
          abort("Failed to commit release prep changes.") unless @git.commit_all(msg)
          true
        end
      end

      def push!
        branch = current_branch
        abort("Could not determine current branch to push.") unless branch

        if use_all_remote?
          puts "$ git push all #{branch}"
          success = @git.push("all", branch)
          unless success
            warn("Normal push to 'all' failed; retrying with force push...")
            @git.push("all", branch, force: true)
          end
          return
        end

        remotes = []
        remotes << "origin" if has_remote?("origin") && !skipped_remote?("origin")
        remotes |= github_remote_candidates
        remotes |= gitlab_remote_candidates
        remotes |= codeberg_remote_candidates
        remotes.uniq!

        if remotes.empty?
          puts "$ git push #{branch}"
          success = @git.push(nil, branch)
          unless success
            warn("Normal push failed; retrying with force push...")
            @git.push(nil, branch, force: true)
          end
          return
        end

        remotes.each do |remote|
          puts "$ git push #{remote} #{branch}"
          success = @git.push(remote, branch)
          unless success
            warn("Push to #{remote} failed; retrying with force push...")
            @git.push(remote, branch, force: true)
          end
        end
      end

      def emit_run_start
        Kettle::Ndjson.emit_event(
          @event_recorder,
          "run_start",
          command: "release",
          root: @root,
          start_step: @start_step,
          skipped_steps: @skip_steps,
          local_ci: @local_ci,
          ci_workflows: @ci_workflows,
          skipped_remotes: @skip_remotes
        )
      end

      def emit_command_event(command, status, reason: nil)
        event = {
          phase: "release",
          index: @command_events.length + 1,
          name: command_event_name(command),
          status: status,
          reason: reason,
          command: command,
          changed_files: []
        }
        @command_events << event unless status == "started"
        Kettle::Ndjson.emit_step_event(@event_recorder, "command_step", event, phase: "release", index: event[:index])
      end

      def command_event_name(command)
        command.to_s.split(/\s+/, 3).first(2).join("_").gsub(/[^A-Za-z0-9_]+/, "_").sub(/_+\z/, "")
      end

      def record_diagnostic(kind, message, severity:, blocking:)
        diagnostic = {
          kind: kind,
          severity: severity,
          message: message.to_s,
          blocking: blocking
        }
        @diagnostics << diagnostic
        Kettle::Ndjson.emit_diagnostic_event(@event_recorder, diagnostic, index: @diagnostics.length)
      end

      def finish_release_report(status:, error:)
        return if @finished_report

        duration_ms = @started_at ? duration_ms_since(@started_at) : nil
        @finished_report = {
          command: "release",
          root: @root,
          version: safe_detect_version,
          gem_name: safe_detect_gem_name,
          start_step: @start_step,
          skipped_steps: @skip_steps,
          local_ci: @local_ci,
          ci_workflows: @ci_workflows,
          skipped_remotes: @skip_remotes,
          status: status,
          error_class: error&.class&.name,
          error_message: error&.message,
          duration_ms: duration_ms,
          command_events: @command_events,
          diagnostics: @diagnostics,
          diagnostics_count: @diagnostics.length,
          phase_timings: @event_recorder.phase_timings
        }.compact
        Kettle::Ndjson.emit_summary_event(@event_recorder, @finished_report)
        write_release_report(@finished_report)
        @json_io.puts(JSON.pretty_generate(@finished_report)) if @json_output
      end

      def write_release_report(report)
        return unless @report_path

        FileUtils.mkdir_p(File.dirname(@report_path))
        File.write(@report_path, "#{JSON.pretty_generate(report)}\n")
      end

      def with_machine_stdout_redirect
        return yield unless @json_output || @event_stream

        previous_stdout = $stdout
        $stdout = $stderr
        yield
      ensure
        $stdout = previous_stdout if previous_stdout
      end

      def human_output
        (@json_output || @event_stream) ? $stderr : $stdout
      end

      def safe_detect_version
        detect_version
      rescue
        nil
      end

      def safe_detect_gem_name
        detect_gem_name
      rescue
        nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def duration_ms_since(started_at)
        ((monotonic_time - started_at) * 1000).round(3)
      end

      def push_tags!
        # After release, push tags to remotes according to policy:
        # 1) If a remote named "all" exists, push tags only to it.
        # 2) Otherwise, if other remotes exist, push tags to each of them.
        # 3) If no remotes are configured, push tags using default remote.
        if use_all_remote?
          ok = @git.push_tags("all")
          warn("Push tags to 'all' reported failure.") unless ok
          return
        end

        remotes = active_remotes
        remotes -= ["all"] if remotes
        if remotes.nil? || remotes.empty?
          ok = @git.push_tags(nil)
          warn("Push tags (default remote) reported failure.") unless ok
        else
          remotes.each do |remote|
            ok = @git.push_tags(remote)
            warn("Push tags to #{remote} reported failure.") unless ok
          end
        end
      end

      def detect_trunk_branch
        out, ok = git_output(["remote", "show", "origin"])
        abort("Failed to get origin remote info.") unless ok
        m = out.lines.find { |l| l.include?("HEAD branch") }
        abort("Unable to detect trunk branch from origin.") unless m
        m.split.last
      end

      def checkout!(branch)
        ok = @git.checkout(branch)
        abort("Failed to checkout #{branch}") unless ok
      end

      def pull!(branch)
        ok = @git.pull("origin", branch)
        abort("Failed to pull origin #{branch}") unless ok
      end

      def current_branch
        @git.current_branch
      end

      def list_remotes
        @git.remotes
      end

      def remotes_with_urls
        @git.remotes_with_urls
      end

      def remote_url(name)
        @git.remote_url(name)
      end

      def github_remote_candidates
        active_remote_candidates(remotes_with_urls.select { |n, u| u.include?("github.com") }.keys)
      end

      def gitlab_remote_candidates
        active_remote_candidates(remotes_with_urls.select { |n, u| u.include?("gitlab.com") }.keys)
      end

      def codeberg_remote_candidates
        active_remote_candidates(remotes_with_urls.select { |n, u| u.include?("codeberg.org") }.keys)
      end

      def preferred_github_remote
        cands = github_remote_candidates
        return if cands.empty?

        # Prefer explicitly named GitHub remotes first, then origin (only if it points to GitHub), else the first candidate
        explicit = cands.find { |n| n == "github" } || cands.find { |n| n == "gh" }
        return explicit if explicit
        return "origin" if cands.include?("origin")

        cands.first
      end

      def parse_github_owner_repo(url)
        Kettle::Dev::CIHelpers.parse_hosted_repo(url, "github.com") || [nil, nil]
      end

      def has_remote?(name)
        list_remotes.include?(name)
      end

      def skipped_remote?(name)
        @skip_remotes.include?(name)
      end

      def active_remotes
        list_remotes.reject { |remote| skipped_remote?(remote) }
      end

      def active_remote_candidates(candidates)
        candidates.reject { |remote| skipped_remote?(remote) }
      end

      def use_all_remote?
        has_remote?("all") && @skip_remotes.empty?
      end

      def remote_branch_exists?(remote, branch)
        _out, ok = git_output(["show-ref", "--verify", "--quiet", "refs/remotes/#{remote}/#{branch}"])
        ok
      end

      def ahead_behind_counts(local_ref, remote_ref)
        out, ok = git_output(["rev-list", "--left-right", "--count", "#{local_ref}...#{remote_ref}"])
        return [0, 0] unless ok && !out.empty?

        parts = out.split
        left = parts[0].to_i
        right = parts[1].to_i
        [left, right]
      end

      def trunk_behind_remote?(trunk, remote)
        return false unless remote_branch_exists?(remote, trunk)

        _ahead, behind = ahead_behind_counts(trunk, "#{remote}/#{trunk}")
        behind.positive?
      end

      def ensure_trunk_synced_before_push!(trunk, feature)
        if has_remote?("all")
          remotes = active_remotes
          skipped = list_remotes.select { |remote| skipped_remote?(remote) }
          puts "Remote 'all' detected. Fetching from active remotes and enforcing strict trunk parity..."
          puts "Skipping configured remotes: #{skipped.join(", ")}" unless skipped.empty?
          remotes.each do |remote|
            next if remote == "all"

            fetch_remote_for_parity!(remote)
          end
          missing_from = []
          remotes.each do |r|
            next if r == "all"

            if remote_branch_exists?(r, trunk)
              _ahead, behind = ahead_behind_counts(trunk, "#{r}/#{trunk}")
              missing_from << r if behind.positive?
            end
          end
          unless missing_from.empty?
            abort("Local #{trunk} is missing commits present on: #{missing_from.join(", ")}. Please sync trunk first.")
          end
          puts "Local #{trunk} has all commits from remotes: #{(remotes - ["all"]).join(", ")}"
          return
        end

        run_cmd!("git fetch origin #{Shellwords.escape(trunk)}")
        if trunk_behind_remote?(trunk, "origin")
          puts "Local #{trunk} is behind origin/#{trunk}. Rebasing..."
          cur = current_branch
          checkout!(trunk) unless cur == trunk
          run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")
          checkout!(feature) unless feature.nil? || feature == trunk
          run_cmd!("git rebase #{Shellwords.escape(trunk)}")
          puts "Rebase complete. Will push updated branch next."
        else
          puts "Local #{trunk} is up to date with origin/#{trunk}."
        end

        gh_remote = preferred_github_remote
        if gh_remote && gh_remote != "origin"
          puts "GitHub remote detected: #{gh_remote}. Fetching #{trunk}..."
          run_cmd!("git fetch #{gh_remote} #{Shellwords.escape(trunk)}")

          left, right = ahead_behind_counts("origin/#{trunk}", "#{gh_remote}/#{trunk}")
          if left.zero? && right.zero?
            puts "origin/#{trunk} and #{gh_remote}/#{trunk} are already in sync."
            return
          end

          checkout!(trunk)
          run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")

          if left.positive? && right.positive?
            puts "origin/#{trunk} and #{gh_remote}/#{trunk} have diverged (#{left} ahead of GH, #{right} behind GH)."
            puts "Choose how to reconcile:"
            puts "  [r] Rebase local/#{trunk} on top of #{gh_remote}/#{trunk} (push to origin)"
            puts "  [m] Merge --no-ff #{gh_remote}/#{trunk} into #{trunk} (push to origin and #{gh_remote})"
            puts "  [a] Abort"
            print("> ")
            choice = Kettle::Dev::InputAdapter.gets&.strip&.downcase
            case choice
            when "r"
              run_cmd!("git rebase #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
              run_cmd!("git push origin #{Shellwords.escape(trunk)}")
              puts "Rebased #{trunk} onto #{gh_remote}/#{trunk} and pushed to origin."
            when "m"
              run_cmd!("git merge --no-ff #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
              run_cmd!("git push origin #{Shellwords.escape(trunk)}")
              run_cmd!("git push #{Shellwords.escape(gh_remote)} #{Shellwords.escape(trunk)}")
              puts "Merged #{gh_remote}/#{trunk} into #{trunk} and pushed to origin and #{gh_remote}."
            else
              abort("Aborted by user. Please reconcile trunks and re-run.")
            end
          elsif right.positive? && left.zero?
            puts "Fast-forwarding #{trunk} to include #{gh_remote}/#{trunk}..."
            run_cmd!("git merge --ff-only #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
            run_cmd!("git push origin #{Shellwords.escape(trunk)}")
          elsif left.positive? && right.zero?
            puts "origin/#{trunk} is ahead of #{gh_remote}/#{trunk}; no action required before push."
          end
        end
      end

      def fetch_remote_for_parity!(remote)
        command = "git fetch #{Shellwords.escape(remote)}"
        attempts = remote_fetch_parity_attempts
        last_error = nil
        attempts.times do |index|
          attempt = index + 1
          puts "Fetching remote '#{remote}' for release parity (attempt #{attempt}/#{attempts})"
          begin
            run_cmd!(command)
            return true
          rescue SystemExit => error
            last_error = error
          rescue => error
            last_error = error
          end
          sleep(remote_fetch_parity_interval) if attempt < attempts
        end

        abort(remote_fetch_failure_message(remote, last_error&.message.to_s))
      end

      def remote_fetch_parity_attempts
        3
      end

      def remote_fetch_parity_interval
        5
      end

      def remote_fetch_failure_message(remote, detail)
        <<~MSG
          Unable to fetch git remote '#{remote}' during release parity checks.
          kettle-release enforces trunk parity across active remotes before publishing.

          If this remote is temporarily unavailable or intentionally not part of this release,
          rerun with one of:
            kettle-release --skip-remotes #{remote}
            K_RELEASE_SKIP_REMOTES=#{remote} kettle-release

          Original failure:
          #{detail}
        MSG
      end

      def merge_feature_into_trunk_and_push!(trunk, feature)
        return if feature.nil? || feature == trunk

        puts "Merging #{feature} into #{trunk} (after CI success)..."
        checkout!(trunk)
        run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")
        run_cmd!("git merge #{Shellwords.escape(feature)}")
        run_cmd!("git push origin #{Shellwords.escape(trunk)}")
        puts "Merged #{feature} into #{trunk} and pushed. The PR (if any) should auto-close."
      end

      def branch_stack_release_branch?(branch, trunk = nil)
        return false if branch.to_s.empty?
        return false if trunk && branch == trunk

        local_kettle_family_release_target_branches.include?(branch)
      end

      def local_kettle_family_release_target_branches
        local_kettle_family_config_paths.each do |path|
          next unless File.file?(path)

          begin
            data = Kettle::Dev.safe_load_yaml_file(path) || {}
            branches = Array(dig_string_keys(data, "release", "target_branches")) +
              Array(dig_string_keys(data, "branches", "release_targets"))
            return branches.map(&:to_s).reject(&:empty?) unless branches.empty?
          rescue Psych::Exception => e
            warn("Ignoring invalid kettle-family config #{Kettle::Dev.display_path(path)}: #{e.message}")
          end
        end
        []
      end

      def local_kettle_family_config_paths
        [
          File.join(@root, ".kettle-family.yml"),
          File.join(@root, ".structuredmerge", "kettle-family.yml")
        ]
      end

      def dig_string_keys(data, *keys)
        keys.reduce(data) do |memo, key|
          break nil unless memo.is_a?(Hash)

          memo[key] || memo[key.to_sym]
        end
      end

      def ensure_signing_setup_or_skip!
        # Treat any non-/true/i value as an explicit skip signal
        return if ENV.fetch("SKIP_GEM_SIGNING", "").casecmp("true").zero?

        user = ENV.fetch("GEM_CERT_USER", ENV["USER"])
        cert_path = File.join(@root, "certs", "#{user}.pem")
        unless File.exist?(cert_path)
          abort(<<~MSG)
            Gem signing appears enabled but no public cert found at:
              #{Kettle::Dev.display_path(cert_path)}
            Add your public key to certs/<USER>.pem (or set GEM_CERT_USER), or set SKIP_GEM_SIGNING to build unsigned.
          MSG
        end
        puts "Found signing cert: #{Kettle::Dev.display_path(cert_path)}"
        puts "When prompted during build/release, enter the PEM password for ~/.ssh/gem-private_key.pem"
      end

      def validate_checksums!(version, stage: "")
        gem_path = checksum_gem_path_for_version!(version)
        actual = compute_sha256(gem_path)
        checks_path = File.join(@root, "checksums", "#{File.basename(gem_path)}.sha256")
        unless File.file?(checks_path)
          abort("Expected checksum file not found: #{checks_path}. Did bin/gem_checksums run?")
        end
        expected = File.read(checks_path).strip
        if actual != expected
          abort(<<~MSG)
            SHA256 mismatch #{stage}:
              gem:   #{gem_path}
              sha256sum: #{actual}
              file: #{checks_path}
              file: #{expected}
            The artifact being released must match the checksummed artifact exactly.
            Retry locally: bundle exec rake build && bin/gem_checksums && bundle exec rake release
          MSG
        else
          puts "Checksum OK #{stage}: #{File.basename(gem_path)}"
        end
      end

      def checksum_gem_path_for_version!(version)
        gem_path = gem_file_for_version(version)
        unless gem_path && File.file?(gem_path)
          abort("Unable to locate built gem for version #{version} in pkg/. Did the build succeed?")
        end
        gem_path
      end

      def gem_file_for_version(version)
        pkg = File.join(@root, "pkg")
        pattern = File.join(pkg, "*.gem")
        gems = Dir[pattern].select { |p| File.basename(p).include?("-#{version}.gem") }
        gems.max
      end

      def compute_sha256(path)
        if system("which sha256sum > /dev/null 2>&1")
          out, _ = Open3.capture2e("sha256sum", path)
          out.split.first
        elsif system("which shasum > /dev/null 2>&1")
          out, _ = Open3.capture2e("shasum", "-a", "256", path)
          out.split.first
        else
          require "digest"
          Digest::SHA256.file(path).hexdigest
        end
      end

      # If GITHUB_TOKEN is present, create a GitHub release for the given version tag.
      # Title: v<version>
      # Body: the CHANGELOG section for this version, followed by the two link references for this version.
      def maybe_create_github_release!(version)
        token = ENV.fetch("GITHUB_TOKEN", "").strip.to_s
        if token.empty?
          warn("GITHUB_TOKEN not set; skipping GitHub release creation. Set GITHUB_TOKEN with repo:public_repo (classic) or contents:write scope.")
          return
        end

        gh_remote = preferred_github_remote
        url = remote_url(gh_remote || "origin")
        owner, repo = parse_github_owner_repo(url)
        unless owner && repo
          warn("GITHUB_TOKEN present but could not determine GitHub owner/repo from remotes. Skipping release creation.")
          return
        end

        section, compare_ref, tag_ref = extract_changelog_for_version(version)
        unless section
          warn("CHANGELOG.md does not contain a section for #{version}. Skipping GitHub release creation.")
          return
        end

        body = +""
        body << section.rstrip
        body << "\n\n"
        body << compare_ref if compare_ref
        body << tag_ref if tag_ref
        # Append funding footer from FUNDING.md if present
        footer = extract_release_notes_footer
        body << "\n" << footer if footer && !footer.strip.empty?

        tag = "v#{version}"
        puts "Creating GitHub release #{owner}/#{repo} #{tag}..."
        ok, msg = github_create_release(owner: owner, repo: repo, token: token, tag: tag, title: tag, body: body)
        if ok
          puts "GitHub release created for #{tag}."
        else
          warn("GitHub release creation skipped/failed: #{msg}")
        end
      end

      # Returns [section_text, compare_ref_line, tag_ref_line]
      def extract_changelog_for_version(version)
        path = File.join(@root, "CHANGELOG.md")
        return [nil, nil, nil] unless File.file?(path)

        content = File.read(path)
        lines = content.lines

        # Find section start
        start_idx = lines.index { |l| l.start_with?("## [#{version}]") }
        return [nil, nil, nil] unless start_idx

        i = start_idx + 1
        # Find next section heading or EOF
        while i < lines.length && !lines[i].start_with?("## [")
          i += 1
        end
        section = lines[start_idx...(i)].join

        # Find link refs (anywhere after Unreleased or at end; simple global scan acceptable)
        compare_ref = lines.find { |l| l.start_with?("[#{version}]: ") }
        tag_ref = lines.find { |l| l.start_with?("[#{version}t]: ") }
        # Ensure newline termination
        compare_ref = compare_ref&.end_with?("\n") ? compare_ref : (compare_ref && compare_ref + "\n")
        tag_ref = tag_ref&.end_with?("\n") ? tag_ref : (tag_ref && tag_ref + "\n")
        [section, compare_ref, tag_ref]
      rescue => e
        warn("Failed to parse CHANGELOG.md: #{e.class}: #{e.message}")
        [nil, nil, nil]
      end

      def extract_release_notes_footer
        path = File.join(@root, "FUNDING.md")
        return unless File.file?(path)

        content = File.read(path)
        start_tag = "<!-- RELEASE-NOTES-FOOTER-START -->"
        end_tag = "<!-- RELEASE-NOTES-FOOTER-END -->"
        s = content.index(start_tag)
        e = content.index(end_tag)
        return unless s && e && e > s

        # Extract between tags, excluding the tags themselves
        block = content[(s + start_tag.length)...e]
        # Normalize: trim trailing whitespace but keep internal formatting
        block = block.lstrip # drop leading newline/space
        block.rstrip
      rescue => e
        warn("[kettle-release] Failed to extract release notes footer from FUNDING.md: #{e.class}: #{e.message}")
        nil
      end

      # POST to GitHub Releases API
      # Returns [ok(Boolean), message(String)]
      def github_create_release(owner:, repo:, token:, tag:, title:, body:)
        uri = URI("https://api.github.com/repos/#{owner}/#{repo}/releases")
        req = Net::HTTP::Post.new(uri)
        req["Accept"] = "application/vnd.github+json"
        req["Authorization"] = "token #{token}"
        req["User-Agent"] = "kettle-dev-release-cli"
        req.body = JSON.dump({
          tag_name: tag,
          name: title,
          body: body,
          draft: false,
          prerelease: false
        })

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(req)
        end

        case res
        when Net::HTTPSuccess, Net::HTTPCreated
          [true, "created"]
        else
          # If release already exists, treat as non-fatal
          if res.code.to_s == "422" && res.body.to_s.include?("already_exists")
            [true, "already exists"]
          else
            [false, "HTTP #{res.code}: #{res.body}"]
          end
        end
      rescue => e
        [false, "#{e.class}: #{e.message}"]
      end
    end
  end
end

class Kettle::Dev::ReleaseCLI::ReleaseCandidate
  attr_accessor :gem_name, :version, :installed_before, :published

  def initialize(gem_name:, version:, installed_before:, published:)
    @gem_name = gem_name
    @version = version
    @installed_before = installed_before
    @published = published
  end
end
