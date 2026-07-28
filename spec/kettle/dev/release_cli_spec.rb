# frozen_string_literal: true

# rubocop:disable RSpec/ReceiveMessages, RSpec/StubbedMock
RSpec.describe Kettle::Dev::ReleaseCLI do
  describe "core behaviors" do
    let(:ci_helpers) { Kettle::Dev::CIHelpers }
    let(:cli) { described_class.new }

    before do |example|
      next if example.metadata[:real_release_lockfiles]

      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(described_class).to receive(:prepare_release_lockfiles_for_commit!)
      allow_any_instance_of(described_class).to receive(:prepare_release_lockfiles_for_release_tasks!)
      allow_any_instance_of(described_class).to receive(:validate_release_lockfiles!)
      # rubocop:enable RSpec/AnyInstance
    end

    def write_style_local(root, ruby_gem)
      gemfile_dir = File.join(root, "gemfiles", "modular")
      FileUtils.mkdir_p(gemfile_dir)
      File.write(File.join(gemfile_dir, "style_local.gemfile"), <<~RUBY)
        # frozen_string_literal: true

        local_gems = %w[rubocop-lts rubocop-lts-rspec #{ruby_gem} standard-rubocop-lts]
      RUBY
    end

    def stub_checksum_artifact(release_cli, version, gem_name = "mygem")
      gem_path = File.join(Dir.pwd, "pkg", "#{gem_name}-#{version}.gem")
      allow(release_cli).to receive(:checksum_gem_path_for_version!).with(version).and_return(gem_path)
      gem_path
    end

    it "detects version and gem name from a temporary project root" do
      Dir.mktmpdir do |root|
        # Arrange version file
        lib_dir = File.join(root, "lib", "mygem")
        FileUtils.mkdir_p(lib_dir)
        File.write(File.join(lib_dir, "version.rb"), <<~RB)
          module Mygem
            VERSION = "1.2.3"
          end
        RB

        # Arrange gemspec
        File.write(File.join(root, "mygem.gemspec"), <<~G)
          Gem::Specification.new do |spec|
            spec.name = "mygem"
          end
        G

        # Stub project root used by ReleaseCLI
        allow(ci_helpers).to receive(:project_root).and_return(root)

        local_cli = described_class.new
        ver = local_cli.send(:detect_version)
        name = local_cli.send(:detect_gem_name)

        expect(ver).to eq("1.2.3")
        expect(name).to eq("mygem")
      end
    end

    it "uses an explicit version override when no version.rb is present" do
      Dir.mktmpdir do |root|
        allow(ci_helpers).to receive(:project_root).and_return(root)
        local_cli = described_class.new(version: "4.5.6")
        expect(local_cli.send(:detect_version)).to eq("4.5.6")
      end
    end

    describe "#run_cmd! (signing env injection)", :real_release_rake do
      it "emits command step events around child commands" do
        io = StringIO.new
        event_stream = Kettle::Ndjson.event_stream(io, types: "command_step")
        local_cli = described_class.new(event_stream: event_stream)
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        allow(Open3).to receive(:capture3).and_return(["", "", status])

        local_cli.send(:run_cmd!, "bin/setup")

        events = io.string.lines.map { |line| JSON.parse(line) }
        expect(events).to contain_exactly(
          include("type" => "command_step", "status" => "started", "command" => "bin/setup", "mark" => ">"),
          include("type" => "command_step", "status" => "ok", "command" => "bin/setup", "mark" => ".")
        )
      end

      it "prefixes SKIP_GEM_SIGNING for 'bundle exec rake build' when env set" do
        stub_env("SKIP_GEM_SIGNING" => "true")
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(Open3).to receive(:capture3).with(kind_of(Hash), "SKIP_GEM_SIGNING=true bundle exec rake build").and_return(["", "", status])
        cli.send(:run_cmd!, "bundle exec rake build")
      end

      it "disables noisy Bundler and debug environment for release child commands" do
        stub_env(
          "DEBUG" => "true",
          "BUNDLE_DEBUG" => "true",
          "BUNDLER_DEBUG" => "true",
          "BUNDLE_VERBOSE" => "true",
          "DEBUG_RESOLVER" => "true"
        )
        allow(ENV).to receive(:to_hash).and_return(ENV.to_hash.merge(
          "DEBUG" => "true",
          "BUNDLE_DEBUG" => "true",
          "BUNDLER_DEBUG" => "true",
          "BUNDLE_VERBOSE" => "true",
          "DEBUG_RESOLVER" => "true"
        ))
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(Open3).to receive(:capture3) do |env, command|
          expect(command).to eq("bin/setup")
          expect(env).to include(
            "DEBUG" => nil,
            "BUNDLE_QUIET" => "true",
            "BUNDLE_DEBUG" => "false",
            "BUNDLER_DEBUG" => "false",
            "BUNDLE_VERBOSE" => "false",
            "DEBUG_RESOLVER" => nil,
            "BUNDLER_DEBUG_RESOLVER" => nil,
            "BUNDLE_SUPPRESS_INSTALL_USING_MESSAGES" => "true"
          )
          ["", "", status]
        end

        cli.send(:run_cmd!, "bin/setup")
      end

      it "sets bundle audit skip env for release child commands when requested" do
        previous_skip_bundle_audit = ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"]
        local_cli = described_class.new(skip_bundle_audit: true)
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(Open3).to receive(:capture3) do |env, command|
          expect(command).to eq("KETTLE_DEV_SKIP_BUNDLE_AUDIT=true bin/rake")
          expect(env.fetch("KETTLE_DEV_SKIP_BUNDLE_AUDIT")).to eq("true")
          ["", "", status]
        end

        local_cli.send(:run_cmd!, "bin/rake")
        expect(ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"]).to eq(previous_skip_bundle_audit)
      end

      it "sets bundle audit skip env around the full release run" do
        previous_skip_bundle_audit = ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"]
        local_cli = described_class.new(skip_bundle_audit: true, skip_steps: "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19")
        expect(local_cli).to receive(:run_pre_release_checks!) do
          expect(ENV.fetch("KETTLE_DEV_SKIP_BUNDLE_AUDIT")).to eq("true")
        end

        local_cli.run
        expect(ENV["KETTLE_DEV_SKIP_BUNDLE_AUDIT"]).to eq(previous_skip_bundle_audit)
      end

      it "preserves noisy environment when release debug is explicitly enabled" do
        stub_env(
          "KETTLE_DEV_DEBUG" => "true",
          "DEBUG" => "true",
          "BUNDLE_DEBUG" => "true",
          "BUNDLER_DEBUG" => "true",
          "BUNDLE_VERBOSE" => "true",
          "DEBUG_RESOLVER" => "true"
        )
        allow(ENV).to receive(:to_hash).and_return(ENV.to_hash.merge(
          "KETTLE_DEV_DEBUG" => "true",
          "DEBUG" => "true",
          "BUNDLE_DEBUG" => "true",
          "BUNDLER_DEBUG" => "true",
          "BUNDLE_VERBOSE" => "true",
          "DEBUG_RESOLVER" => "true"
        ))
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(Open3).to receive(:capture3) do |env, command|
          expect(command).to eq("bin/setup")
          expect(env).to include(
            "KETTLE_DEV_DEBUG" => "true",
            "DEBUG" => "true",
            "BUNDLE_DEBUG" => "true",
            "BUNDLER_DEBUG" => "true",
            "BUNDLE_VERBOSE" => "true",
            "DEBUG_RESOLVER" => "true"
          )
          ["", "", status]
        end

        cli.send(:run_cmd!, "bin/setup")
      end

      it "runs kettle-changelog with the current TTY so its confirmation prompt is visible" do
        allow(described_class).to receive(:system).with(kind_of(Hash), "bundle exec kettle-changelog").and_return(true)
        expect(Open3).not_to receive(:capture3)

        cli.send(:run_cmd!, "bundle exec kettle-changelog")
      end

      it "uses the configured release secrets provider for prompt-bearing release commands" do
        provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword)
        local_cli = described_class.new(secrets_provider: provider)
        runner = instance_double(Kettle::Dev::InteractiveReleaseCommand)
        status = instance_double(Process::Status, success?: true, exitstatus: 0)
        expect(Kettle::Dev::InteractiveReleaseCommand)
          .to receive(:new)
          .with(secrets_provider: provider)
          .and_return(runner)
        expect(runner).to receive(:call).with(kind_of(Hash), "bundle exec rake release").and_return(["", "", status])
        expect(Open3).not_to receive(:capture3)

        local_cli.send(:run_cmd!, "bundle exec rake release")
      end

      it "treats the real 1Password provider as configured" do
        provider = Kettle::Dev::ReleaseSecrets::OnePassword.new(
          "gem_signing_passphrase_source" => "cached"
        )
        local_cli = described_class.new(secrets_provider: provider)

        expect(local_cli.send(:release_secrets_configured?)).to be(true)
        expect(local_cli.send(:release_secrets_provider_label)).to eq("OnePassword")
      end

      it "treats the base release secrets provider as interactive" do
        local_cli = described_class.new(secrets_provider: Kettle::Dev::ReleaseSecrets::Provider.new)

        expect(local_cli.send(:release_secrets_configured?)).to be(false)
        expect(local_cli.send(:release_secrets_provider_label)).to eq("interactive")
      end

      it "skips duplicate test and coverage work in the default task after changelog coverage runs" do
        local_cli = described_class.new
        allow(local_cli).to receive(:run_cmd!)

        local_cli.send(:run_changelog!)

        expect(local_cli.send(:release_default_task_command)).to eq("KETTLE_DEV_SKIP_TESTS=true bin/rake")
      end

      it "keeps the full default task for resumed releases that did not run changelog coverage" do
        local_cli = described_class.new(start_step: 4)

        expect(local_cli.send(:release_default_task_command)).to eq("bin/rake")
      end

      it "fails early when configured release secrets cannot provide the signing passphrase" do
        provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, gem_signing_passphrase: nil)
        local_cli = described_class.new(secrets_provider: provider, yes: true)

        expect {
          local_cli.send(:ensure_release_secrets_ready_for_signing!)
        }.to raise_error(MockSystemExit, /Secret prompts are not allowed when --secrets-provider is set/)
      end
    end

    describe "machine-readable release reports" do
      it "emits run start and summary events and writes the final JSON report" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          FileUtils.mkdir_p(File.join(root, "lib", "mygem"))
          File.write(File.join(root, "lib", "mygem", "version.rb"), "module Mygem; VERSION = \"1.2.3\"; end\n")
          File.write(File.join(root, "mygem.gemspec"), "Gem::Specification.new { |spec| spec.name = \"mygem\" }\n")
          event_io = StringIO.new
          json_io = StringIO.new
          report_path = File.join(root, "tmp", "release-report.json")
          local_cli = described_class.new(
            skip_steps: "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19",
            event_stream: Kettle::Ndjson.event_stream(event_io, types: "run_start,summary"),
            json_output: true,
            json_io: json_io,
            report_path: report_path
          )

          local_cli.run

          events = event_io.string.lines.map { |line| JSON.parse(line) }
          expect(events).to contain_exactly(
            include("type" => "run_start", "command" => "release", "root" => root),
            include("type" => "summary", "command" => "release", "status" => "ok", "version" => "1.2.3", "gem_name" => "mygem")
          )
          expect(JSON.parse(json_io.string)).to include("status" => "ok", "version" => "1.2.3", "gem_name" => "mygem")
          expect(JSON.parse(File.read(report_path))).to include("status" => "ok", "version" => "1.2.3", "gem_name" => "mygem")
        end
      end
    end

    describe "#ensure_bundler_2_7_plus!" do
      it "aborts when bundler is missing" do
        hide_const("Bundler") if defined?(Bundler)
        allow(cli).to receive(:require).with("bundler").and_raise(LoadError)
        expect { cli.send(:ensure_bundler_2_7_plus!) }.to raise_error(MockSystemExit, /Bundler is required/)
      end

      it "aborts when bundler version is too low" do
        stub_const("Bundler", Class.new)
        stub_const("Bundler::VERSION", "2.6.9")
        expect { cli.send(:ensure_bundler_2_7_plus!) }.to raise_error(MockSystemExit, /requires Bundler >= 2.7.0/)
      end

      it "passes when bundler meets minimum" do
        stub_const("Bundler", Class.new)
        stub_const("Bundler::VERSION", "2.7.1")
        expect { cli.send(:ensure_bundler_2_7_plus!) }.not_to raise_error
      end
    end

    describe "#latest_released_versions" do
      let(:response_class) do
        Class.new do
          attr_reader :body
          def initialize(body)
            @body = body
          end

          def is_a?(k)
            k == Net::HTTPSuccess
          end
        end
      end

      it "parses versions and filters prereleases and letters; computes series" do
        versions = [
          {"number" => "1.2.3"},
          {"number" => "1.2.4.pre"},
          {"number" => "1.3.0"},
          {"number" => "2.0.0"},
          {"number" => "1.2.10"},
          {"number" => "1.2.9-alpha"}
        ]
        allow(Kettle::Dev::RubyGemsVersions).to receive(:fetch).with("gemx", version_hint: "1.2.0").and_return(versions)
        overall, series = cli.send(:latest_released_versions, "gemx", "1.2.0")
        expect(overall).to eq("2.0.0")
        expect(series).to eq("1.2.10")
      end

      it "returns [nil, nil] on errors" do
        allow(Kettle::Dev::RubyGemsVersions).to receive(:fetch).and_raise(StandardError)
        overall, series = cli.send(:latest_released_versions, "gemx", "1.2.3")
        expect(overall).to be_nil
        expect(series).to be_nil
      end
    end

    describe "#run_pre_release_checks!" do
      it "runs kettle-pre-release checks from the beginning and invokes kettle-changelog" do
        pre_release = instance_double(Kettle::Dev::PreReleaseCLI, run: nil)
        expect(Kettle::Dev::PreReleaseCLI).to receive(:new).with(check_num: 1).and_return(pre_release)
        expect(cli).to receive(:run_cmd!).with("bundle exec kettle-changelog")

        cli.send(:run_pre_release_checks!)
      end

      it "passes an explicit version override to kettle-changelog" do
        versioned_cli = described_class.new(version: "3.2.1")
        pre_release = instance_double(Kettle::Dev::PreReleaseCLI, run: nil)
        expect(Kettle::Dev::PreReleaseCLI).to receive(:new).with(check_num: 1).and_return(pre_release)
        expect(versioned_cli).to receive(:run_cmd!).with("bundle exec kettle-changelog --version 3.2.1")

        versioned_cli.send(:run_pre_release_checks!)
      end

      it "passes --yes to kettle-changelog when release auto-approval is enabled" do
        yes_cli = described_class.new(yes: true)
        pre_release = instance_double(Kettle::Dev::PreReleaseCLI, run: nil)
        expect(Kettle::Dev::PreReleaseCLI).to receive(:new).with(check_num: 1).and_return(pre_release)
        expect(yes_cli).to receive(:run_cmd!).with("bundle exec kettle-changelog --yes")

        yes_cli.send(:run_pre_release_checks!)
      end
    end

    describe "latest_released_versions (integration with RubyGems.org via VCR)" do
      it "fetches real versions for kettle-dev and does not report a 1.2.x series", :check_output do
        # Use VCR to record once then replay. We avoid making any strong assertion on the exact
        # version numbers to keep the test resilient, but we do assert no 1.2.x appears for this gem.
        cassette = "ruby_gems_versions_kettle_dev"
        overall, series = nil, nil
        # Ensure any previous stubs on Net::HTTP from unit tests do not apply here; we want a real HTTP call (recorded by VCR)
        allow(Net::HTTP).to receive(:get_response).and_call_original
        VCR.use_cassette(cassette) do
          overall, series = cli.send(:latest_released_versions, "kettle-dev", "1.0.0")
        end
        # Basic sanity
        expect(overall).to be_a(String).or be_nil
        expect(series).to be_a(String).or be_nil
        # The reported bug was seeing a 1.2.x. Assert that does not occur for this gem.
        expect(overall&.start_with?("1.2.")).to be(false)
        expect(series&.start_with?("1.2.")).to be(false)
      end
    end

    describe "#commit_release_prep!" do
      it "returns false when no changes" do
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:add_all).and_return(true)
        allow(cli).to receive(:git_output).with(%w[status --porcelain]).and_return(["", true])
        expect(cli.send(:commit_release_prep!, "1.0.0")).to be false
      end

      it "commits and returns true when there are changes" do
        git = cli.instance_variable_get(:@git)
        allow(cli).to receive(:git_output).with(%w[status --porcelain]).and_return([" M file", true])
        expect(git).to receive(:add_all).and_return(true)
        expect(git).to receive(:commit_all).with("🔖 Prepare release v1.0.0").and_return(true)
        expect(cli.send(:commit_release_prep!, "1.0.0")).to be true
      end
    end

    describe "#push!" do
      it "aborts when branch is unknown" do
        allow(cli).to receive(:current_branch).and_return(nil)
        expect { cli.send(:push!) }.to raise_error(MockSystemExit, /Could not determine current branch/)
      end

      it "pushes to 'all' and force-pushes on failure" do
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push).with("all", "feat").and_return(false)
        expect(git).to receive(:push).with("all", "feat", force: true)
        cli.send(:push!)
      end

      it "pushes branch with no remotes and force on failure" do
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        allow(cli).to receive(:has_remote?).with("origin").and_return(false)
        allow(cli).to receive(:github_remote_candidates).and_return([])
        allow(cli).to receive(:gitlab_remote_candidates).and_return([])
        allow(cli).to receive(:codeberg_remote_candidates).and_return([])
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push).with(nil, "feat").and_return(false)
        expect(git).to receive(:push).with(nil, "feat", force: true)
        cli.send(:push!)
      end

      it "pushes to multiple remotes and force on failures" do
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        allow(cli).to receive(:has_remote?).with("origin").and_return(true)
        allow(cli).to receive(:github_remote_candidates).and_return(["github"])
        allow(cli).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        allow(cli).to receive(:codeberg_remote_candidates).and_return([])
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push).with("origin", "feat").and_return(true)
        expect(git).to receive(:push).with("github", "feat").and_return(false)
        expect(git).to receive(:push).with("github", "feat", force: true)
        expect(git).to receive(:push).with("gitlab", "feat").and_return(true)
        cli.send(:push!)
      end

      it "does not push through the all aggregate when remotes are skipped" do
        cli = described_class.new(skip_remotes: "cb")
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:has_remote?).with("origin").and_return(true)
        allow(cli).to receive(:github_remote_candidates).and_return(["origin", "gh"])
        allow(cli).to receive(:gitlab_remote_candidates).and_return(["gl"])
        allow(cli).to receive(:codeberg_remote_candidates).and_return([])
        git = cli.instance_variable_get(:@git)
        expect(git).not_to receive(:push).with("all", "feat")
        expect(git).to receive(:push).with("origin", "feat").and_return(true)
        expect(git).to receive(:push).with("gh", "feat").and_return(true)
        expect(git).to receive(:push).with("gl", "feat").and_return(true)
        cli.send(:push!)
      end
    end

    describe "git and system helpers" do
      it "detects trunk branch from origin remote output (still via git command)" do
        out = "Remote HEAD branch: main\n  HEAD branch: main\n"
        allow(cli).to receive(:git_output).with(%w[remote show origin]).and_return([out, true])
        expect(cli.send(:detect_trunk_branch)).to eq("main")
      end

      it "parses remotes_with_urls and candidates" do
        git = cli.instance_variable_get(:@git)
        allow(git).to receive(:remotes_with_urls).and_return({
          "origin" => "git@github.com:me/repo.git",
          "github" => "https://github.com/me/repo.git",
          "gl" => "https://gitlab.com/me/repo",
          "cb" => "git@codeberg.org:me/repo.git"
        })
        urls = cli.send(:remotes_with_urls)
        expect(urls["origin"]).to include("github.com")
        expect(cli.send(:github_remote_candidates)).to include("origin", "github")
        expect(cli.send(:gitlab_remote_candidates)).to include("gl")
        expect(cli.send(:codeberg_remote_candidates)).to include("cb")
        expect(cli.send(:preferred_github_remote)).to eq("github")
      end

      it "filters skipped remotes from candidates" do
        cli = described_class.new(skip_remotes: "cb,github")
        git = cli.instance_variable_get(:@git)
        allow(git).to receive(:remotes_with_urls).and_return({
          "origin" => "git@github.com:me/repo.git",
          "github" => "https://github.com/me/repo.git",
          "cb" => "git@codeberg.org:me/repo.git"
        })

        expect(cli.send(:github_remote_candidates)).to eq(["origin"])
        expect(cli.send(:codeberg_remote_candidates)).to be_empty
      end

      it "parses github owner/repo from ssh and https and fails otherwise" do
        expect(cli.send(:parse_github_owner_repo, "git@github.com:user/repo.git")).to eq(%w[user repo])
        expect(cli.send(:parse_github_owner_repo, "git+ssh://git@github.com/user/repo.git")).to eq(%w[user repo])
        expect(cli.send(:parse_github_owner_repo, "ssh://git@github.com/user/repo.git")).to eq(%w[user repo])
        expect(cli.send(:parse_github_owner_repo, "https://github.com/user/repo")).to eq(%w[user repo])
        expect(cli.send(:parse_github_owner_repo, "ssh://gitlab.com/user/repo")).to eq([nil, nil])
      end

      it "computes ahead/behind from git output and handles empty" do
        allow(cli).to receive(:git_output).and_return(["3\t2", true], ["", false])
        expect(cli.send(:ahead_behind_counts, "a", "b")).to eq([3, 2])
        expect(cli.send(:ahead_behind_counts, "a", "b")).to eq([0, 0])
      end

      it "checks trunk_behind_remote? based on remote branch and counts" do
        allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 1])
        expect(cli.send(:trunk_behind_remote?, "main", "origin")).to be true
      end

      it "skips GitHub pull request setup when releasing from trunk" do
        allow(cli).to receive(:current_branch).and_return("main")
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        expect(cli).not_to receive(:github_pull_request_for_branch)

        cli.send(:ensure_github_pull_request_for_ci!)
      end

      it "reuses an open GitHub pull request before CI monitoring", :check_output do
        allow(cli).to receive(:current_branch).and_return("feature/release")
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:preferred_github_remote).and_return("origin")
        allow(cli).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
        allow(cli).to receive(:github_pull_request_for_branch).with(
          owner: "me",
          repo: "repo",
          branch: "feature/release",
          base: "main"
        ).and_return({"number" => 42, "url" => "https://github.com/me/repo/pull/42"})
        expect(cli).not_to receive(:create_github_pull_request!)

        cli.send(:ensure_github_pull_request_for_ci!)
      end

      it "creates a GitHub pull request before CI monitoring when none is open" do
        allow(cli).to receive(:current_branch).and_return("feature/release")
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:preferred_github_remote).and_return("origin")
        allow(cli).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
        allow(cli).to receive(:github_pull_request_for_branch).and_return(nil)

        expect(cli).to receive(:create_github_pull_request!).with(
          owner: "me",
          repo: "repo",
          branch: "feature/release",
          base: "main"
        )

        cli.send(:ensure_github_pull_request_for_ci!)
      end

      it "git_output trims and returns success flag" do
        # Ensure GitAdapter is used and its output is trimmed
        adapter = instance_double(Kettle::Dev::GitAdapter)
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:capture).with(["rev-parse"]).and_return([" abc\n", true])
        cli = described_class.new
        out, ok = cli.send(:git_output, ["rev-parse"])
        expect(out).to eq("abc")
        expect(ok).to be(true)
      end

      it "maybe_run_local_ci_before_push! handles missing act command", :check_output do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
          # Enable run
          cli = described_class.new
          # Raise from system("act", "--version", ...)
          allow(cli).to receive(:system).and_wrap_original do |orig, *args|
            if args[0] == "act" && args[1] == "--version"
              raise "no act"
            else
              orig.call(*args)
            end
          end
          stub_env("K_RELEASE_LOCAL_CI" => "true")
          expect { cli.send(:maybe_run_local_ci_before_push!, false) }.to output(/Skipping local CI: 'act' command not found/).to_stdout
        end
      end

      it "selects workflow via ENV without extension (adds .yml) and prefers .yaml for locked_deps", :check_output do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          dir = File.join(root, ".github", "workflows")
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, "ci.yml"), "name: CI\n")
          File.write(File.join(dir, "locked_deps.yaml"), "name: Lock\n")

          cli = described_class.new
          # Make "act --version" succeed and capture the -W <path> invocation
          ran_paths = []
          allow(cli).to receive(:system).and_wrap_original do |orig, *args|
            if args[0] == "act" && args[1] == "--version"
              true
            elsif args[0] == "act" && args[1] == "-W"
              ran_paths << args[2]
              true # pretend local CI succeeded
            else
              orig.call(*args)
            end
          end

          # Case 1: ENV chooses "ci" -> should append .yml
          # Case 1: ENV chooses "ci" -> should append .yml
          stub_env("K_RELEASE_LOCAL_CI" => "true", "K_RELEASE_LOCAL_CI_WORKFLOW" => "ci")
          expect { cli.send(:maybe_run_local_ci_before_push!, false) }.not_to raise_error
          expect(ran_paths.last).to end_with("/ci.yml")

          # Case 2: No ENV, candidates include locked_deps.yaml -> choose .yaml variant
          ran_paths.clear
          stub_env("K_RELEASE_LOCAL_CI" => "true", "K_RELEASE_LOCAL_CI_WORKFLOW" => "")
          expect { cli.send(:maybe_run_local_ci_before_push!, false) }.not_to raise_error
          expect(ran_paths.last).to end_with("/locked_deps.yaml")
        end
      end

      it "preferred_github_remote returns origin when present" do
        cli = described_class.new
        expect(cli.send(:preferred_github_remote)).to eq("origin")
      end

      it "remote_branch_exists? reflects git show-ref success flag" do
        cli = described_class.new
        allow(cli).to receive(:git_output).and_return(["", false])
        expect(cli.send(:remote_branch_exists?, "origin", "main")).to be(false)
      end
    end

    describe "#ensure_trunk_synced_before_push!" do
      it "enforces strict parity when remote 'all' is present and aborts if missing commits" do
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:list_remotes).and_return(%w[all origin github])
        expect(cli).to receive(:run_cmd!).with("git fetch origin")
        expect(cli).to receive(:run_cmd!).with("git fetch github")
        allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 1])
        allow(cli).to receive(:remote_branch_exists?).with("github", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "github/main").and_return([0, 0])
        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.to raise_error(MockSystemExit, /missing commits present on: origin/)
      end

      it "reports parity when all remotes are synced" do
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:list_remotes).and_return(%w[all origin])
        expect(cli).to receive(:run_cmd!).with("git fetch origin")
        allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 0])
        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.not_to raise_error
      end

      it "adds a skip-remotes hint when an active remote cannot be fetched" do
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:list_remotes).and_return(%w[all origin cb])
        allow(cli).to receive(:remote_fetch_parity_attempts).and_return(2)
        allow(cli).to receive(:remote_fetch_parity_interval).and_return(0)
        expect(cli).to receive(:run_cmd!).with("git fetch origin")
        expect(cli).to receive(:run_cmd!).with("git fetch cb").twice.and_raise(MockSystemExit, "Command failed: git fetch cb (exit 128)")
        expect(cli).to receive(:sleep).with(0).once

        expect do
          cli.send(:ensure_trunk_synced_before_push!, "main", "feat")
        end.to raise_error(MockSystemExit) { |error|
          expect(error.message).to include("Unable to fetch git remote 'cb'")
          expect(error.message).to include("kettle-release --skip-remotes cb")
          expect(error.message).to include("K_RELEASE_SKIP_REMOTES=cb kettle-release")
          expect(error.message).to include("Command failed: git fetch cb")
        }
      end

      it "retries transient remote fetch failures before checking parity" do
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:list_remotes).and_return(%w[all cb])
        allow(cli).to receive(:remote_fetch_parity_attempts).and_return(3)
        allow(cli).to receive(:remote_fetch_parity_interval).and_return(0)
        expect(cli).to receive(:run_cmd!).with("git fetch cb").ordered.and_raise(MockSystemExit, "transient")
        expect(cli).to receive(:sleep).with(0).ordered
        expect(cli).to receive(:run_cmd!).with("git fetch cb").ordered
        allow(cli).to receive(:remote_branch_exists?).with("cb", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "cb/main").and_return([0, 0])

        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.not_to raise_error
      end

      it "skips configured remotes while enforcing all-remote parity" do
        cli = described_class.new(skip_remotes: "cb")
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        allow(cli).to receive(:list_remotes).and_return(%w[all origin cb])
        expect(cli).to receive(:run_cmd!).with("git fetch origin")
        expect(cli).not_to receive(:run_cmd!).with("git fetch cb")
        allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
        allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 0])
        expect(cli).not_to receive(:remote_branch_exists?).with("cb", "main")

        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.not_to raise_error
      end

      it "rebases when trunk is behind origin and then rebases feature" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        # Allow additional run_cmd! calls (e.g., fetching a GitHub remote) without failing this example
        allow(cli).to receive(:run_cmd!)

        allow(cli).to receive(:trunk_behind_remote?).with("main", "origin").and_return(true)
        allow(cli).to receive(:current_branch).and_return("feat")
        expect(cli).to receive(:checkout!).with("main")
        expect(cli).to receive(:checkout!).with("feat")

        cli.send(:ensure_trunk_synced_before_push!, "main", "feat")

        # Assert key run_cmd! invocations happened, regardless of any extra fetches against other remotes
        expect(cli).to have_received(:run_cmd!).with("git fetch origin main")
        expect(cli).to have_received(:run_cmd!).with("git pull --rebase origin main")
        expect(cli).to have_received(:run_cmd!).with("git rebase main")
      end

      it "handles github remote sync fast-forward case" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([0, 2])
        expect(cli).to receive(:checkout!).with("main")
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        expect(cli).to receive(:run_cmd!).with("git merge --ff-only github/main")
        expect(cli).to receive(:run_cmd!).with("git push origin main")
        cli.send(:ensure_trunk_synced_before_push!, "main", "feat")
      end

      it "prints no action when origin ahead of github" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([3, 0])
        expect(cli).to receive(:checkout!).with("main")
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        cli.send(:ensure_trunk_synced_before_push!, "main", "feat")
      end
    end

    describe "#merge_feature_into_trunk_and_push!" do
      it "no-ops when feature is trunk" do
        expect(cli.send(:merge_feature_into_trunk_and_push!, "main", "main")).to be_nil
      end

      it "merges and pushes when feature differs" do
        expect(cli).to receive(:checkout!).with("main")
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        expect(cli).to receive(:run_cmd!).with("git merge feat")
        expect(cli).to receive(:run_cmd!).with("git push origin main")
        cli.send(:merge_feature_into_trunk_and_push!, "main", "feat")
      end
    end

    describe "kettle-family branch stack releases" do
      it "detects local release target branches from .kettle-family.yml" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, ".kettle-family.yml"), <<~YAML)
            release:
              target_branches:
                - r1_8-even-v0
                - main
          YAML
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new

          expect(local_cli.send(:branch_stack_release_branch?, "r1_8-even-v0", "main")).to be(true)
          expect(local_cli.send(:branch_stack_release_branch?, "main", "main")).to be(false)
          expect(local_cli.send(:branch_stack_release_branch?, "feature", "main")).to be(false)
        end
      end

      it "skips trunk sync, merge, and checkout for a local branch-stack release branch" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, ".kettle-family.yml"), <<~YAML)
            release:
              target_branches:
                - r1_8-even-v0
                - main
          YAML
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new(start_step: 8, skip_steps: "9,10,13,14,15,16,17,18,19")
          allow(local_cli).to receive(:detect_trunk_branch).and_return("main")
          allow(local_cli).to receive(:current_branch).and_return("r1_8-even-v0")
          allow(local_cli).to receive(:push!)
          allow(local_cli).to receive(:monitor_workflows_after_push!)
          allow(local_cli).to receive(:ensure_signing_setup_or_skip!)
          allow(local_cli).to receive(:validate_checksums!)
          allow(local_cli).to receive(:push_tags!)

          expect(local_cli).not_to receive(:ensure_trunk_synced_before_push!)
          expect(local_cli).not_to receive(:merge_feature_into_trunk_and_push!)
          expect(local_cli).not_to receive(:checkout!)
          expect(local_cli).not_to receive(:pull!)

          expect { local_cli.run }.not_to raise_error
        end
      end
    end

    describe "#ensure_signing_setup_or_skip!" do
      it "returns early when SKIP_GEM_SIGNING is set to true" do
        stub_env("SKIP_GEM_SIGNING" => "true")
        expect(cli.send(:ensure_signing_setup_or_skip!)).to be_nil
      end

      it "aborts when cert is missing and signing enabled" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          other = described_class.new
          stub_env("SKIP_GEM_SIGNING" => "false", "GEM_CERT_USER" => "alice", "USER" => "bob")
          expect { other.send(:ensure_signing_setup_or_skip!) }.to raise_error(MockSystemExit, /no public cert/)
        end
      end

      it "passes when cert exists" do
        Dir.mktmpdir do |root|
          FileUtils.mkdir_p(File.join(root, "certs"))
          File.write(File.join(root, "certs", "bob.pem"), "cert")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          other = described_class.new
          stub_env("SKIP_GEM_SIGNING" => nil, "GEM_CERT_USER" => nil, "USER" => "bob")
          expect { other.send(:ensure_signing_setup_or_skip!) }.not_to raise_error
        end
      end
    end

    describe "checksums helpers" do
      it "validates checksums success and failure and locates gem by version" do
        Dir.mktmpdir do |root|
          pkg = File.join(root, "pkg")
          chks = File.join(root, "checksums")
          FileUtils.mkdir_p(pkg)
          FileUtils.mkdir_p(chks)
          gem_a = File.join(pkg, "mygem-1.0.0.gem")
          File.write(gem_a, "hello world")
          expected = Digest::SHA256.hexdigest("hello world")
          File.write(File.join(chks, "mygem-1.0.0.gem.sha256"), expected)
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          expect { local_cli.send(:validate_checksums!, "1.0.0", stage: "stage") }.not_to raise_error
          File.write(File.join(chks, "mygem-1.0.0.gem.sha256"), "deadbeef")
          expect { local_cli.send(:validate_checksums!, "1.0.0", stage: "stage") }.to raise_error(MockSystemExit, /SHA256 mismatch/)
        end
      end

      it "compute_sha256 falls back to Digest when no sha utilities" do
        Dir.mktmpdir do |root|
          file = File.join(root, "file.bin")
          File.binwrite(file, "abc")
          allow(cli).to receive(:system).with("which sha256sum > /dev/null 2>&1").and_return(false)
          allow(cli).to receive(:system).with("which shasum > /dev/null 2>&1").and_return(false)
          expect(cli.send(:compute_sha256, file)).to eq(Digest::SHA256.hexdigest("abc"))
        end
      end
    end

    describe "#monitor_workflows_after_push!" do
      before do
        allow(cli).to receive(:ensure_github_pull_request_for_ci!)
        allow(ci_helpers).to receive(:project_root).and_return(Dir.pwd)
        allow(ci_helpers).to receive(:current_branch).and_return("feat")
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return("origin")
        allow(Kettle::Dev::CIMonitor).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
      end

      it "aborts when branch cannot be determined" do
        allow(ci_helpers).to receive(:current_branch).and_return(nil)
        expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(MockSystemExit, /Could not determine current branch/)
      end

      it "passes when GitHub workflows all succeed" do
        allow(ci_helpers).to receive(:workflows_list).and_return(%w[ci.yml lint.yml])
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
        run1 = {"html_url" => "http://example/1"}
        run2 = {"html_url" => "http://example/2"}
        allow(ci_helpers).to receive(:current_head_sha).and_return("abc123")
        allow(ci_helpers).to receive(:latest_run).with(owner: "me", repo: "repo", workflow_file: "ci.yml", branch: "feat", require_head: true, head_sha: "abc123").and_return(run1)
        allow(ci_helpers).to receive(:latest_run).with(owner: "me", repo: "repo", workflow_file: "lint.yml", branch: "feat", require_head: true, head_sha: "abc123").and_return(run2)
        allow(ci_helpers).to receive(:success?).and_return(true)
        expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
        expect(cli).to have_received(:ensure_github_pull_request_for_ci!)
      end

      it "passes an explicit normalized workflow subset to the CI monitor" do
        release_cli = described_class.new(ci_workflows: "current,style.yml")
        allow(release_cli).to receive(:ensure_github_pull_request_for_ci!)
        allow(Kettle::Dev::CIMonitor).to receive(:monitor_all!)

        release_cli.send(:monitor_workflows_after_push!)

        expect(Kettle::Dev::CIMonitor).to have_received(:monitor_all!).with(
          restart_hint: "bundle exec kettle-release start_step=10",
          workflows: %w[current.yml style.yml]
        )
      end

      it "uses K_RELEASE_CI_WORKFLOWS when no explicit workflow subset is passed" do
        stub_env("K_RELEASE_CI_WORKFLOWS" => "current,style.yml")
        release_cli = described_class.new
        allow(release_cli).to receive(:ensure_github_pull_request_for_ci!)
        allow(Kettle::Dev::CIMonitor).to receive(:monitor_all!)

        release_cli.send(:monitor_workflows_after_push!)

        expect(Kettle::Dev::CIMonitor).to have_received(:monitor_all!).with(
          restart_hint: "bundle exec kettle-release start_step=10",
          workflows: %w[current.yml style.yml]
        )
      end

      it "aborts when a GitHub workflow fails" do
        allow(ci_helpers).to receive(:workflows_list).and_return(["ci.yml"])
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return([])
        allow(ci_helpers).to receive(:current_head_sha).and_return("abc123")
        run = {"html_url" => "http://example/ci"}
        allow(ci_helpers).to receive(:latest_run).and_return(run)
        allow(ci_helpers).to receive(:success?).and_return(false)
        allow(ci_helpers).to receive(:failed?).and_return(true)
        expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(MockSystemExit, /Workflow failed: .*start_step=10/)
      end

      it "handles GitLab pipeline success" do
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return(nil)
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
        allow(ci_helpers).to receive(:repo_info_gitlab).and_return(%w[me repo])
        pipe = {"web_url" => "http://gitlab/pipeline"}
        allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
        allow(ci_helpers).to receive(:gitlab_success?).and_return(true)
        allow(ci_helpers).to receive(:gitlab_failed?).and_return(false)
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
      end

      it "aborts when GitLab pipeline fails" do
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return(nil)
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
        allow(ci_helpers).to receive(:repo_info_gitlab).and_return(%w[me repo])
        pipe = {"web_url" => "http://gitlab/pipeline"}
        allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
        allow(ci_helpers).to receive(:gitlab_success?).and_return(false)
        allow(ci_helpers).to receive(:gitlab_failed?).and_return(true)
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(MockSystemExit, /Pipeline failed: .*start_step=10/)
      end

      it "aborts when no CI configured" do
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return(nil)
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return([])
        expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(MockSystemExit, /CI configuration not detected/)
      end
    end

    describe "release lockfile validation", :real_release_lockfiles do
      def with_release_root
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          yield(root, described_class.new)
        end
      end

      it "flags local path remotes and registry checksums without sha256 while allowing path source gems" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            PATH
              remote: .
              specs:
                demo (0.1.0)

            PATH
              remote: /home/pboling/src/my/kettle-dev/kettle-soup-cover
              specs:
                kettle-soup-cover (3.0.5)

            GEM
              remote: https://gem.coop/
              specs:
                addressable (2.9.0)
                rack (3.2.1)

            CHECKSUMS
              addressable (2.9.0) sha256=abc123
              demo (0.1.0)
              kettle-soup-cover (3.0.5)
              rack (3.2.1)

            BUNDLED WITH
               4.0.17
          LOCK

          diagnostics = local_cli.send(:release_lockfile_diagnostics, File.join(root, "Gemfile.lock"))

          expect(diagnostics.join("\n")).to include("has local path remote")
          expect(diagnostics.join("\n")).to include("CHECKSUMS has no sha256 for rack 3.2.1")
          expect(diagnostics.join("\n")).not_to include("CHECKSUMS has no sha256 for kettle-soup-cover 3.0.5")
          expect(diagnostics.join("\n")).not_to include("CHECKSUMS has no sha256 for demo 0.1.0")
        end
      end

      it "normalizes dirty release lockfiles before validating the release prep commit" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                addressable (2.9.0)
                kettle-soup-cover (3.0.5)

            CHECKSUMS
              addressable (2.9.0) sha256=abc123
              kettle-soup-cover (3.0.5)

            BUNDLED WITH
               4.0.17
          LOCK

          expect(local_cli).to receive(:run_cmd!).with(
            a_string_matching(/KETTLE_DEV_DEV=false.*BUNDLE_GEMFILE=.*Gemfile.*bundle lock --update --add-checksums/)
          ) do
            File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
              GEM
                remote: https://rubygems.org/
                specs:
                  kettle-soup-cover (3.0.4)

              CHECKSUMS
                kettle-soup-cover (3.0.4) sha256=abc123

              BUNDLED WITH
                 4.0.17
            LOCK
          end
          expect(local_cli).not_to receive(:run_cmd!).with(a_string_matching(/bundle lock --update kettle-soup-cover/))

          expect { local_cli.send(:prepare_release_lockfiles_for_commit!) }.not_to raise_error
        end
      end

      it "normalizes the appraisal root lockfile instead of writing the default Gemfile.lock" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                rake (13.4.2)

            CHECKSUMS
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK
          File.write(File.join(root, "Appraisal.root.gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Appraisal.root.gemfile.lock"), <<~LOCK)
            PATH
              remote: .
              specs:
                demo (0.1.0)

            GEM
              remote: https://rubygems.org/
              specs:
                rake (13.4.2)

            CHECKSUMS
              demo (0.1.0)
              rake (13.4.2)

            BUNDLED WITH
               4.0.17
          LOCK

          expect(local_cli).to receive(:run_cmd!).with(
            a_string_matching(
              /BUNDLE_GEMFILE=.*Appraisal\.root\.gemfile.*BUNDLE_LOCKFILE=.*Appraisal\.root\.gemfile\.lock.*bundle lock --update --add-checksums/
            )
          ).ordered do
            File.write(File.join(root, "Appraisal.root.gemfile.lock"), <<~LOCK)
              GEM
                remote: https://rubygems.org/
                specs:
                  rake (13.4.2)

              CHECKSUMS
                rake (13.4.2) sha256=abc123

              BUNDLED WITH
                 4.0.17
            LOCK
          end
          expect(local_cli).to receive(:run_cmd!).with(
            a_string_matching(/BUNDLE_GEMFILE=.*Gemfile.*BUNDLE_LOCKFILE=.*Gemfile\.lock.*bundle lock --update --add-checksums/)
          ).ordered do
            File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
              GEM
                remote: https://rubygems.org/
                specs:
                  rake (13.4.2)

              CHECKSUMS
                rake (13.4.2) sha256=abc123

              BUNDLED WITH
                 4.0.17
            LOCK
          end
          expect(local_cli).not_to receive(:run_cmd!).with(a_string_matching(/bundle lock --update rake/))

          expect { local_cli.send(:prepare_release_lockfiles_for_commit!) }.not_to raise_error
        end
      end

      it "retries release task lockfile resets when the configured source has not caught up yet" do
        with_release_root do |_root, local_cli|
          resetter = instance_double(Kettle::Dev::LockfileReset)
          attempts = 0
          allow(resetter).to receive(:reset) do
            attempts += 1
            raise "Bundler::GemNotFound: Could not find gem 'gitmoji-regex (~> 2.0, >= 2.0.7)' in locally installed gems." if attempts == 1

            []
          end
          allow(local_cli).to receive(:lockfile_reset).and_return(resetter)
          allow(local_cli).to receive(:release_lockfile_paths).and_return([])
          allow(local_cli).to receive(:release_availability_probe_attempts).and_return(2)
          allow(local_cli).to receive(:release_availability_probe_interval).and_return(0)
          expect(local_cli).to receive(:sleep).with(0).once

          expect do
            local_cli.send(:reset_release_lockfiles!, stage: "before release task bundle installs")
          end.to output(/attempt 1\/2.*could not resolve a gem.*attempt 2\/2.*reset complete/m).to_stdout
          expect(attempts).to eq(2)
        end
      end

      it "ignores generated appraisal lockfiles outside the release lockfile set" do
        with_release_root do |root, local_cli|
          gemfiles_dir = File.join(root, "gemfiles")
          FileUtils.mkdir_p(gemfiles_dir)
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                rake (13.4.2)

            CHECKSUMS
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK
          File.write(File.join(gemfiles_dir, "dep_heads.gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                benchmark (0.5.0)
                rake (13.4.2)

            CHECKSUMS
              benchmark (0.5.0)
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK

          expect(local_cli.send(:release_lockfile_paths)).to eq([File.join(root, "Gemfile.lock")])
          expect { local_cli.send(:validate_release_lockfiles!, stage: "before push") }.not_to raise_error
        end
      end

      it "aborts before release prep commit when normalization cannot repair registry checksums" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                addressable (2.9.0)
                kettle-soup-cover (3.0.5)

            CHECKSUMS
              addressable (2.9.0) sha256=abc123
              kettle-soup-cover (3.0.5)

            BUNDLED WITH
               4.0.17
          LOCK

          allow(local_cli).to receive(:run_cmd!)

          expect do
            local_cli.send(:prepare_release_lockfiles_for_commit!)
          end.to raise_error(MockSystemExit, /Release lockfile validation failed before release prep commit/)
        end
      end

      it "resets and amends release lockfiles that become invalid before push" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            PATH
              remote: ../demo
              specs:
                demo (0.1.0)

            GEM
              remote: https://rubygems.org/
              specs:
                kettle-soup-cover (3.0.5)

            CHECKSUMS
              kettle-soup-cover (3.0.5)
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK

          expect(local_cli).to receive(:run_cmd!).with(
            a_string_matching(/bundle lock --update --add-checksums/)
          ) do
            File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
              GEM
                remote: https://rubygems.org/
                specs:
                  demo (0.1.0)
                  kettle-soup-cover (3.0.5)

              CHECKSUMS
                demo (0.1.0) sha256=abc123
                kettle-soup-cover (3.0.5) sha256=def456

              BUNDLED WITH
                 4.0.17
            LOCK
          end
          resetter = Kettle::Dev::LockfileReset.new(root: root, command_runner: ->(command) { local_cli.send(:run_cmd!, command) })
          allow(resetter).to receive(:local_workspace_gem_names).and_return(Set.new)
          local_cli.instance_variable_set(:@lockfile_reset, resetter)
          git = local_cli.instance_variable_get(:@git)
          allow(git).to receive(:diff_head_quiet?).with(File.join(root, "Gemfile.lock")).and_return(false)
          expect(git).to receive(:add_paths).with([File.join(root, "Gemfile.lock")]).and_return(true)
          expect(git).to receive(:commit_amend_no_edit).and_return(true)

          expect do
            local_cli.send(:validate_release_lockfiles!, stage: "before push")
          end.to output(/Release lockfile validation found 2 issue\(s\) before push:.*has local path remote.*Running one fallback release lockfile reset before push.*diagnostics cleared; amending release prep commit with 1 lockfile\(s\)/m).to_stdout
        end
      end

      it "reports when the fallback reset restores dirty lockfiles to the release prep commit" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            PATH
              remote: ../demo
              specs:
                demo (0.1.0)

            GEM
              remote: https://rubygems.org/
              specs:
                kettle-soup-cover (3.0.5)

            CHECKSUMS
              kettle-soup-cover (3.0.5)
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK

          expect(local_cli).to receive(:run_cmd!).with(
            a_string_matching(/bundle lock --update --add-checksums/)
          ) do
            File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
              GEM
                remote: https://rubygems.org/
                specs:
                  demo (0.1.0)
                  kettle-soup-cover (3.0.5)

              CHECKSUMS
                demo (0.1.0) sha256=abc123
                kettle-soup-cover (3.0.5) sha256=def456

              BUNDLED WITH
                 4.0.17
            LOCK
          end
          git = local_cli.instance_variable_get(:@git)
          resetter = Kettle::Dev::LockfileReset.new(root: root, command_runner: local_cli.method(:run_cmd!))
          allow(resetter).to receive(:local_workspace_gem_names).and_return(Set.new)
          local_cli.instance_variable_set(:@lockfile_reset, resetter)
          allow(git).to receive(:diff_head_quiet?).with(File.join(root, "Gemfile.lock")).and_return(false, true)
          expect(git).not_to receive(:add_paths)
          expect(git).not_to receive(:commit_amend_no_edit)

          expect do
            local_cli.send(:validate_release_lockfiles!, stage: "before push")
          end.to output(/Release lockfile validation found 2 issue\(s\) before push:.*diagnostics cleared by restoring tracked lockfiles to the release prep commit; no amend is needed/m).to_stdout
        end
      end

      it "reports unrepaired release lockfile diagnostics before push" do
        with_release_root do |root, local_cli|
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            PATH
              remote: ../demo
              specs:
                demo (0.1.0)

            GEM
              remote: https://rubygems.org/
              specs:
                kettle-soup-cover (3.0.5)

            CHECKSUMS
              kettle-soup-cover (3.0.5)
              rake (13.4.2) sha256=abc123

            BUNDLED WITH
               4.0.17
          LOCK

          allow(local_cli).to receive(:run_cmd!)

          expect do
            expect do
              local_cli.send(:validate_release_lockfiles!, stage: "before push")
            end.to raise_error(MockSystemExit, /Release lockfile validation failed before push/)
          end.to output(/Release lockfile validation found 2 issue\(s\) before push:.*Release lockfile reset did not repair all before-push issues:.*has local path remote/m).to_stdout
        end
      end

      it "runs the release lockfile guard before committing release prep" do
        local_cli = described_class.new(start_step: 6, skip_steps: "7,8,9,10,11,12,13,14,15,16,17,18,19")
        allow(local_cli).to receive(:detect_version).and_return("9.9.9")
        allow(local_cli).to receive(:detect_gem_name).and_return("mygem")

        expect(local_cli).to receive(:prepare_release_lockfiles_for_commit!).ordered
        expect(local_cli).to receive(:ensure_git_user!).ordered
        expect(local_cli).to receive(:commit_release_prep!).with("9.9.9").ordered.and_return(false)

        expect { local_cli.run }.not_to raise_error
      end

      it "repairs a stale appraisal root lock before appraisal generation can install it" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new(start_step: 5, skip_steps: "6,7,8,9,10,11,12,13,14,15,16,17,18,19")
          File.write(File.join(root, "Appraisals"), "# appraisals\n")
          File.write(File.join(root, "Gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                rake (13.4.2)

            CHECKSUMS
              rake (13.4.2) sha256=abc123
          LOCK
          File.write(File.join(root, "Appraisal.root.gemfile"), "source \"https://rubygems.org\"\n")
          File.write(File.join(root, "Appraisal.root.gemfile.lock"), <<~LOCK)
            GEM
              remote: https://rubygems.org/
              specs:
                kettle-starfish (9.9.9)

            CHECKSUMS
              kettle-starfish (9.9.9) sha256=localonly
          LOCK
          commands = []
          command_runner = lambda do |command|
            commands << command
            if command.include?("BUNDLE_LOCKFILE=#{File.join(root, "Appraisal.root.gemfile.lock")}")
              File.write(File.join(root, "Appraisal.root.gemfile.lock"), <<~LOCK)
                GEM
                  remote: https://rubygems.org/
                  specs:
                    rake (13.4.2)

                CHECKSUMS
                  rake (13.4.2) sha256=abc123
              LOCK
            elsif command.include?("BUNDLE_LOCKFILE=#{File.join(root, "Gemfile.lock")}")
              File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
                GEM
                  remote: https://rubygems.org/
                  specs:
                    rake (13.4.2)

                CHECKSUMS
                rake (13.4.2) sha256=abc123
              LOCK
            end
          end
          resetter = Kettle::Dev::LockfileReset.new(root: root, command_runner: command_runner)
          allow(resetter).to receive(:local_workspace_gem_names).and_return(Set["kettle-starfish"])
          local_cli.instance_variable_set(:@lockfile_reset, resetter)
          allow(local_cli).to receive(:run_cmd!) do |command|
            commands << command
          end

          expect { local_cli.run }.not_to raise_error
          appraisal_reset_index = commands.index { |command| command.include?("BUNDLE_LOCKFILE=#{File.join(root, "Appraisal.root.gemfile.lock")}") }
          appraisal_generate_index = commands.index("bin/rake appraisal:generate")
          expect(appraisal_reset_index).not_to be_nil
          expect(appraisal_generate_index).not_to be_nil
          expect(appraisal_reset_index).to be < appraisal_generate_index
        end
      end

      it "validates lockfiles before monitoring CI on a step 10 resume" do
        local_cli = described_class.new(start_step: 10, skip_steps: "11,12,13,14,15,16,17,18,19")
        allow(local_cli).to receive(:detect_version).and_return("9.9.9")
        allow(local_cli).to receive(:detect_gem_name).and_return("mygem")

        expect(local_cli).to receive(:validate_release_lockfiles!).with(stage: "before CI monitoring").ordered
        expect(local_cli).to receive(:monitor_workflows_after_push!).ordered

        expect { local_cli.run }.not_to raise_error
      end
    end

    describe "#run" do
      around do |ex|
        orig_stdin = $stdin
        begin
          ex.run
        ensure
          $stdin = orig_stdin
        end
      end

      it "aborts when current version is not greater than latest released for series" do
        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!) # skip real check
        allow(cli).to receive(:detect_version).and_return("1.2.3")
        allow(cli).to receive(:detect_gem_name).and_return("mygem")
        allow(cli).to receive(:latest_released_versions).and_return(%w[1.2.3 1.2.3]) # equal -> abort
        # First prompt will not be reached because we abort earlier
        expect { cli.run }.to raise_error(MockSystemExit, /version bump required/)
      end

      it "runs happy path when RubyGems.org is offline and Appraisals exist and SKIP_GEM_SIGNING is set", :jruby_head_release_flow do
        # Make prompts auto-accept via input adapter
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")

        stub_env("SKIP_GEM_SIGNING" => "true")

        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("9.9.9")
        allow(cli).to receive(:detect_gem_name).and_return("mygem")
        gem_path = stub_checksum_artifact(cli, "9.9.9")
        allow(cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(cli).to receive(:validate_copyright_years!)
        allow(cli).to receive(:update_readme_kloc_badge!)
        allow(cli).to receive(:update_rakefile_example_header!)

        # Stub commands that would actually run
        allow(cli).to receive(:run_cmd!).and_return(true)
        allow(cli).to receive(:ensure_git_user!)
        allow(cli).to receive(:commit_release_prep!).and_return(true)
        allow(cli).to receive(:maybe_run_local_ci_before_push!)
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:current_branch).and_return("feature/my-work")
        allow(cli).to receive(:ensure_trunk_synced_before_push!)
        allow(cli).to receive(:push!)
        allow(cli).to receive(:monitor_workflows_after_push!)
        allow(cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(cli).to receive(:checkout!)
        allow(cli).to receive(:pull!)
        allow(cli).to receive(:ensure_signing_setup_or_skip!)
        allow(cli).to receive(:push_tags!)
        allow(cli).to receive(:confirm_release_candidate_available!)
        expect(cli).to receive(:validate_checksums!).with("9.9.9", stage: "after release")

        # Appraisals exists at repo root; ensure truthy branch executes
        expect { cli.run }.not_to raise_error

        # Ensure the initial build/release commands were attempted
        expect(cli).to have_received(:run_pre_release_checks!)
        expect(cli).to have_received(:run_cmd!).with("bin/setup")
        expect(cli).to have_received(:run_cmd!).with("bin/rake")
        expect(cli).to have_received(:run_cmd!).with("bin/rake appraisal:generate")
        expect(cli).to have_received(:run_cmd!).with("bin/rake yard")
        expect(cli).to have_received(:run_cmd!).with("bundle exec rake build")
        expect(cli).to have_received(:run_cmd!).with("bundle exec rake release")
        expect(cli).to have_received(:run_cmd!).with("bin/gem_checksums #{gem_path}")
      end

      it "runs local-ci mode without pushing until after the gem is published", :jruby_head_release_flow do
        local_cli = described_class.new(local_ci: true)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
        stub_env("SKIP_GEM_SIGNING" => "true", "GITHUB_TOKEN" => nil)

        allow(local_cli).to receive(:run_pre_release_checks!)
        allow(local_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(local_cli).to receive(:detect_version).and_return("9.9.9")
        allow(local_cli).to receive(:detect_gem_name).and_return("mygem")
        stub_checksum_artifact(local_cli, "9.9.9")
        allow(local_cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(local_cli).to receive(:validate_copyright_years!)
        allow(local_cli).to receive(:update_readme_kloc_badge!)
        allow(local_cli).to receive(:update_rakefile_example_header!)
        allow(local_cli).to receive(:run_cmd!).and_return(true)
        allow(local_cli).to receive(:ensure_git_user!)
        allow(local_cli).to receive(:commit_release_prep!).and_return(true)
        allow(local_cli).to receive(:ensure_signing_setup_or_skip!)
        allow(local_cli).to receive(:validate_checksums!)
        allow(local_cli).to receive(:maybe_create_github_release!)

        expect(local_cli).to receive(:maybe_run_local_ci_before_push!).with(true, force: true).ordered
        expect(local_cli).not_to receive(:ensure_trunk_synced_before_push!)
        expect(local_cli).not_to receive(:monitor_workflows_after_push!)
        expect(local_cli).not_to receive(:merge_feature_into_trunk_and_push!)
        expect(local_cli).not_to receive(:checkout!)
        expect(local_cli).not_to receive(:pull!)
        expect(local_cli).to receive(:release_gem_and_tag_locally!).with("9.9.9").ordered
        expect(local_cli).to receive(:push!).ordered
        expect(local_cli).to receive(:push_tags!).ordered

        expect { local_cli.run }.not_to raise_error
        expect(local_cli).to have_received(:run_pre_release_checks!)
        expect(local_cli).to have_received(:run_cmd!).with("bundle exec rake build")
        expect(local_cli).not_to have_received(:run_cmd!).with("bundle exec rake release")
      end

      it "uses appraisal:update when explicitly requested", :jruby_head_release_flow do
        update_cli = described_class.new(appraisal_task: "appraisal:update")
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
        stub_env("SKIP_GEM_SIGNING" => "true")

        allow(update_cli).to receive(:run_pre_release_checks!)
        allow(update_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(update_cli).to receive(:detect_version).and_return("9.9.9")
        allow(update_cli).to receive(:detect_gem_name).and_return("mygem")
        stub_checksum_artifact(update_cli, "9.9.9")
        allow(update_cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(update_cli).to receive(:validate_copyright_years!)
        allow(update_cli).to receive(:update_readme_kloc_badge!)
        allow(update_cli).to receive(:update_rakefile_example_header!)
        allow(update_cli).to receive(:run_cmd!).and_return(true)
        allow(update_cli).to receive(:ensure_git_user!)
        allow(update_cli).to receive(:commit_release_prep!).and_return(true)
        allow(update_cli).to receive(:maybe_run_local_ci_before_push!)
        allow(update_cli).to receive(:detect_trunk_branch).and_return("main")
        allow(update_cli).to receive(:current_branch).and_return("feature/my-work")
        allow(update_cli).to receive(:ensure_trunk_synced_before_push!)
        allow(update_cli).to receive(:push!)
        allow(update_cli).to receive(:monitor_workflows_after_push!)
        allow(update_cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(update_cli).to receive(:checkout!)
        allow(update_cli).to receive(:pull!)
        allow(update_cli).to receive(:ensure_signing_setup_or_skip!)
        allow(update_cli).to receive(:push_tags!)
        allow(update_cli).to receive(:validate_checksums!)
        allow(update_cli).to receive(:confirm_release_candidate_available!)

        expect { update_cli.run }.not_to raise_error

        expect(update_cli).to have_received(:run_cmd!).with("bin/rake appraisal:update")
      end

      it "skips appraisal generation when Appraisals file missing", :jruby_head_release_flow do
        # Accept initial prompt via input adapter
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")

        stub_env("SKIP_GEM_SIGNING" => "true")

        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("9.9.9")
        allow(cli).to receive(:detect_gem_name).and_return("mygem")
        stub_checksum_artifact(cli, "9.9.9")
        allow(cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(cli).to receive(:validate_copyright_years!)
        allow(cli).to receive(:update_readme_kloc_badge!)
        allow(cli).to receive(:update_rakefile_example_header!)
        allow(cli).to receive(:run_cmd!).and_return(true)
        allow(cli).to receive(:ensure_git_user!)
        allow(cli).to receive(:commit_release_prep!).and_return(false)
        allow(cli).to receive(:maybe_run_local_ci_before_push!)
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:ensure_trunk_synced_before_push!)
        allow(cli).to receive(:push!)
        allow(cli).to receive(:monitor_workflows_after_push!)
        allow(cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(cli).to receive(:checkout!)
        allow(cli).to receive(:pull!)
        allow(cli).to receive(:ensure_signing_setup_or_skip!)
        allow(cli).to receive(:push_tags!)
        allow(cli).to receive(:validate_checksums!)
        allow(cli).to receive(:confirm_release_candidate_available!)

        # Force File.file?(Appraisals) false just for that path
        appraisals_path = File.join(Kettle::Dev::CIHelpers.project_root, "Appraisals")
        allow(File).to receive(:file?).and_wrap_original do |m, path|
          if path == appraisals_path
            false
          else
            m.call(path)
          end
        end

        expect { cli.run }.not_to raise_error
        expect(cli).to have_received(:run_cmd!).with("bin/setup")
        expect(cli).to have_received(:run_cmd!).with("bin/rake")
        expect(cli).not_to have_received(:run_cmd!).with("bin/rake appraisal:generate")
        expect(cli).to have_received(:run_cmd!).with("bin/rake yard")
      end

      it "aborts when signing enabled on tty and user declines prompt", :jruby_head_release_flow do
        allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(true)
        # Two prompts: first we answer 'y' to proceed, second we answer 'n' to abort signing
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n", "n\n")

        stub_env("SKIP_GEM_SIGNING" => nil, "CI" => "true")

        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("9.9.9")
        allow(cli).to receive(:detect_gem_name).and_return("mygem")
        allow(cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(cli).to receive(:validate_copyright_years!)
        allow(cli).to receive(:update_readme_kloc_badge!)
        allow(cli).to receive(:update_rakefile_example_header!)

        # Stub through to the signing gate
        allow(cli).to receive(:run_cmd!).and_return(true)
        allow(cli).to receive(:ensure_git_user!)
        allow(cli).to receive(:commit_release_prep!).and_return(true)
        allow(cli).to receive(:maybe_run_local_ci_before_push!)
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:current_branch).and_return("feat")
        allow(cli).to receive(:ensure_trunk_synced_before_push!)
        allow(cli).to receive(:push!)
        allow(cli).to receive(:monitor_workflows_after_push!)
        allow(cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(cli).to receive(:checkout!)
        allow(cli).to receive(:pull!)

        expect { cli.run }.to raise_error(MockSystemExit, /SKIP_GEM_SIGNING=true/)
      end

      it "auto-approves release confirmation prompts when yes mode is enabled", :jruby_head_release_flow do
        yes_cli = described_class.new(yes: true)
        allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(true)
        expect(Kettle::Dev::InputAdapter).not_to receive(:gets)

        stub_env("SKIP_GEM_SIGNING" => nil, "CI" => "true")

        allow(yes_cli).to receive(:run_pre_release_checks!)
        allow(yes_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(yes_cli).to receive(:detect_version).and_return("9.9.9")
        allow(yes_cli).to receive(:detect_gem_name).and_return("mygem")
        stub_checksum_artifact(yes_cli, "9.9.9")
        allow(yes_cli).to receive(:latest_released_versions).and_return([nil, nil])
        allow(yes_cli).to receive(:validate_copyright_years!)
        allow(yes_cli).to receive(:update_readme_kloc_badge!)
        allow(yes_cli).to receive(:update_rakefile_example_header!)
        allow(yes_cli).to receive(:run_cmd!).and_return(true)
        allow(yes_cli).to receive(:ensure_git_user!)
        allow(yes_cli).to receive(:commit_release_prep!).and_return(true)
        allow(yes_cli).to receive(:maybe_run_local_ci_before_push!)
        allow(yes_cli).to receive(:detect_trunk_branch).and_return("main")
        allow(yes_cli).to receive(:current_branch).and_return("feat")
        allow(yes_cli).to receive(:ensure_trunk_synced_before_push!)
        allow(yes_cli).to receive(:push!)
        allow(yes_cli).to receive(:monitor_workflows_after_push!)
        allow(yes_cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(yes_cli).to receive(:checkout!)
        allow(yes_cli).to receive(:pull!)
        allow(yes_cli).to receive(:ensure_signing_setup_or_skip!)
        allow(yes_cli).to receive(:push_tags!)
        allow(yes_cli).to receive(:validate_checksums!)
        allow(yes_cli).to receive(:confirm_release_candidate_available!)

        expect { yes_cli.run }.not_to raise_error
      end

      it "aborts before release setup when pre-release checks fail" do
        expect(cli).to receive(:run_pre_release_checks!).and_raise(MockSystemExit.new("pre-release failed"))
        expect(cli).not_to receive(:ensure_bundler_2_7_plus!)

        expect { cli.run }.to raise_error(MockSystemExit, /pre-release failed/)
      end

      it "skips pre-release checks when resuming at step 1" do
        resumed_cli = described_class.new(start_step: 1)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
        allow(resumed_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(resumed_cli).to receive(:detect_version).and_return("9.9.9")
        allow(resumed_cli).to receive(:detect_gem_name).and_return("mygem")
        allow(resumed_cli).to receive(:latest_released_versions).and_return([nil, nil])
        expect(resumed_cli).not_to receive(:run_pre_release_checks!)

        expect { resumed_cli.run }.to raise_error(MockSystemExit, /please update version.rb/)
      end

      it "skips pre-release checks when resuming after step 1" do
        resumed_cli = described_class.new(start_step: 2)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
        allow(resumed_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(resumed_cli).to receive(:detect_version).and_return("9.9.9")
        allow(resumed_cli).to receive(:detect_gem_name).and_return("mygem")
        allow(resumed_cli).to receive(:latest_released_versions).and_return([nil, nil])
        expect(resumed_cli).not_to receive(:run_pre_release_checks!)

        expect { resumed_cli.run }.to raise_error(MockSystemExit, /please update version.rb/)
      end
    end

    describe "#run version sanity messaging and rescue" do
      around do |ex|
        orig_stdin = $stdin
        begin
          ex.run
        ensure
          $stdin = orig_stdin
        end
      end

      it "prints series info when latest overall is different series and continues", :jruby_head_release_flow do
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("1.2.10")
        allow(cli).to receive(:detect_gem_name).and_return("mygem")
        stub_checksum_artifact(cli, "1.2.10")
        allow(cli).to receive(:latest_released_versions).and_return(%w[1.3.0 1.2.9]) # triggers line 36 and 47 branch
        allow(cli).to receive(:validate_copyright_years!)
        allow(cli).to receive(:update_readme_kloc_badge!)
        allow(cli).to receive(:update_rakefile_example_header!)
        allow(cli).to receive(:run_cmd!).and_return(true)
        allow(cli).to receive(:ensure_git_user!)
        allow(cli).to receive(:commit_release_prep!).and_return(false)
        allow(cli).to receive(:maybe_run_local_ci_before_push!)
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:current_branch).and_return("main")
        allow(cli).to receive(:ensure_trunk_synced_before_push!)
        allow(cli).to receive(:push!)
        allow(cli).to receive(:monitor_workflows_after_push!)
        allow(cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(cli).to receive(:checkout!)
        allow(cli).to receive(:pull!)
        stub_env("SKIP_GEM_SIGNING" => "true")
        allow(cli).to receive(:ensure_signing_setup_or_skip!)
        allow(cli).to receive(:validate_checksums!)
        allow(cli).to receive(:confirm_release_candidate_available!)
        expect { cli.run }.not_to raise_error
      end

      it "rescues failures from RubyGems.org release check and proceeds to user prompt" do
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("1.2.3")
        allow(cli).to receive(:detect_gem_name).and_raise(StandardError.new("boom"))
        expect { cli.run }.to raise_error(MockSystemExit, /please update version.rb/)
      end
    end

    describe "#run sanity-check branches" do
      it "aborts on downgrade when latest target is higher", :check_output do
        cli = described_class.new
        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("1.2.3")
        allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
        # overall is higher than current series; no series-specific latest -> target=nil would skip, so provide same-series higher
        allow(cli).to receive(:latest_released_versions).and_return(%w[1.2.4 1.2.4]) # [overall, for_series]
        expect do
          cli.run
        end.to raise_error(MockSystemExit, /version must be bumped above 1.2.4/)
      end

      it "prints offline message when target cannot be determined even though overall present", :check_output, :jruby_head_release_flow do
        cli = described_class.new
        allow(cli).to receive(:run_pre_release_checks!)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("1.2.3")
        allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
        stub_checksum_artifact(cli, "1.2.3", "kettle-dev")
        # Simulate overall from a newer series (2.0.0) but no latest for current series -> target=nil
        allow(cli).to receive(:latest_released_versions).and_return(["2.0.0", nil])
        # Proceed past the prompt and subsequent steps quickly
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y")
        allow(cli).to receive(:validate_copyright_years!)
        allow(cli).to receive(:update_readme_kloc_badge!)
        allow(cli).to receive(:update_rakefile_example_header!)
        # Skip remaining heavy steps
        allow(cli).to receive(:run_cmd!)
        allow(cli).to receive(:ensure_git_user!)
        allow(cli).to receive(:detect_trunk_branch).and_return("main")
        allow(cli).to receive(:current_branch).and_return("feature")
        allow(cli).to receive(:monitor_workflows_after_push!)
        allow(cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(cli).to receive(:checkout!)
        allow(cli).to receive(:pull!)
        allow(cli).to receive(:ensure_signing_setup_or_skip!)
        allow(cli).to receive(:validate_checksums!)
        allow(cli).to receive(:maybe_create_github_release!)
        allow(cli).to receive(:push_tags!)
        allow(cli).to receive(:confirm_release_candidate_available!)
        # Make final detection trivial
        allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")

        # Ensure the offline message was printed during run
        expect { cli.run }.to output(/Could not determine latest released version from RubyGems.org/).to_stdout
      end

      it "prints fallback final message when gem name detection fails", :check_output do
        cli = described_class.new(start_step: 19)
        allow(cli).to receive(:ensure_bundler_2_7_plus!)
        allow(cli).to receive(:detect_version).and_return("3.2.1")
        # Make detect_gem_name raise so rescue branch prints fallback line
        allow(cli).to receive(:detect_gem_name).and_raise(StandardError, "boom")

        expect { cli.run }.to output(/Release v3.2.1 Complete/).to_stdout
      end
    end

    describe "#ensure_git_user!" do
      it "passes when name and email are configured" do
        allow(cli).to receive(:git_output).with(%w[config user.name]).and_return(["Alice", true])
        allow(cli).to receive(:git_output).with(%w[config user.email]).and_return(["alice@example.com", true])
        expect { cli.send(:ensure_git_user!) }.not_to raise_error
      end

      it "aborts when missing name or email" do
        allow(cli).to receive(:git_output).with(%w[config user.name]).and_return(["", true])
        allow(cli).to receive(:git_output).with(%w[config user.email]).and_return(["", false])
        expect { cli.send(:ensure_git_user!) }.to raise_error(MockSystemExit, /Git user.name or user.email/)
      end
    end

    describe "#maybe_run_local_ci_before_push!" do
      it "returns immediately when mode is disabled" do
        stub_env("K_RELEASE_LOCAL_CI" => nil)
        expect(cli.send(:maybe_run_local_ci_before_push!, true)).to be_nil
      end

      it "asks the user and proceeds on default yes, but skips when act not found" do
        stub_env("K_RELEASE_LOCAL_CI" => "ask")
        allow($stdin).to receive(:gets).and_return("\n") # default yes
        allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(false)
        expect { cli.send(:maybe_run_local_ci_before_push!, true) }.not_to raise_error
      end

      it "runs with act when chosen workflow is nil due to no candidates" do
        stub_env("K_RELEASE_LOCAL_CI" => "true")
        allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(true)
        allow(ci_helpers).to receive(:project_root).and_return(Dir.pwd)
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        expect { cli.send(:maybe_run_local_ci_before_push!, false) }.not_to raise_error
      end

      it "skips when selected workflow file does not exist" do
        Dir.mktmpdir do |root|
          stub_env("K_RELEASE_LOCAL_CI" => "true")
          allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(true)
          allow(ci_helpers).to receive(:project_root).and_return(root)
          # Create workflows dir but not the chosen file
          wf_dir = File.join(root, ".github", "workflows")
          FileUtils.mkdir_p(wf_dir)
          allow(ci_helpers).to receive(:workflows_list).and_return(["ci.yml"]) # chosen => first
          expect { cli.send(:maybe_run_local_ci_before_push!, false) }.not_to raise_error
        end
      end

      it "runs act successfully on an existing workflow" do
        Dir.mktmpdir do |root|
          stub_env("K_RELEASE_LOCAL_CI" => "true")
          allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(true)
          allow(ci_helpers).to receive(:project_root).and_return(root)
          wf_dir = File.join(root, ".github", "workflows")
          FileUtils.mkdir_p(wf_dir)
          file_path = File.join(wf_dir, "locked_deps.yml")
          File.write(file_path, "name: demo")
          allow(ci_helpers).to receive(:workflows_list).and_return(["locked_deps.yml"]) # will pick locked_deps.yml
          expect(cli).to receive(:system).with("act", "-W", file_path).and_return(true)
          expect { cli.send(:maybe_run_local_ci_before_push!, false) }.not_to raise_error
        end
      end

      it "aborts on act failure and rolls back when committed" do
        Dir.mktmpdir do |root|
          stub_env("K_RELEASE_LOCAL_CI" => "true")
          allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(true)
          allow(ci_helpers).to receive(:project_root).and_return(root)
          wf_dir = File.join(root, ".github", "workflows")
          FileUtils.mkdir_p(wf_dir)
          file_path = File.join(wf_dir, "ci.yml")
          File.write(file_path, "name: ci")
          allow(ci_helpers).to receive(:workflows_list).and_return(["ci.yml"])
          expect(cli).to receive(:system).with("act", "-W", file_path).and_return(false)
          git = cli.instance_variable_get(:@git)
          expect(git).to receive(:reset_soft).with("HEAD^").and_return(true)
          expect { cli.send(:maybe_run_local_ci_before_push!, true) }.to raise_error(MockSystemExit, /local CI failure/)
        end
      end

      it "aborts when forced and act is unavailable" do
        allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(false)
        expect { cli.send(:maybe_run_local_ci_before_push!, false, force: true) }.to raise_error(MockSystemExit, /Local CI requires 'act'/)
      end

      it "aborts when forced and no workflows are available" do
        allow(cli).to receive(:system).with("act", "--version", out: File::NULL, err: File::NULL).and_return(true)
        allow(ci_helpers).to receive(:project_root).and_return(Dir.pwd)
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        expect { cli.send(:maybe_run_local_ci_before_push!, false, force: true) }.to raise_error(MockSystemExit, /requires at least one workflow/)
      end
    end

    describe "#release_gem_and_tag_locally!" do
      it "creates a local tag and pushes the built gem without pushing git refs" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          pkg = File.join(root, "pkg")
          FileUtils.mkdir_p(pkg)
          gem_path = File.join(pkg, "mygem-1.2.3.gem")
          File.write(gem_path, "gem")
          local_cli = described_class.new

          allow(local_cli).to receive(:git_output).with(["rev-parse", "-q", "--verify", "refs/tags/v1.2.3"]).and_return(["", false])
          git = local_cli.instance_variable_get(:@git)
          expect(git).to receive(:tag_annotated).with("v1.2.3", "v1.2.3").ordered.and_return(true)
          expect(local_cli).to receive(:run_cmd!).with("gem push #{gem_path}").ordered
          expect(local_cli).to receive(:run_release_availability_probe).ordered do |candidate|
            expect(candidate.published).to be(true)
            true
          end
          expect(Kettle::Dev::RubyGemsVersions).to receive(:mark_released).with("mygem", "1.2.3")

          local_cli.send(:release_gem_and_tag_locally!, "1.2.3")
        end
      end

      it "does not recreate an existing local tag" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          pkg = File.join(root, "pkg")
          FileUtils.mkdir_p(pkg)
          gem_path = File.join(pkg, "mygem-1.2.3.gem")
          File.write(gem_path, "gem")
          local_cli = described_class.new

          allow(local_cli).to receive(:git_output).with(["rev-parse", "-q", "--verify", "refs/tags/v1.2.3"]).and_return(["abc", true])
          git = local_cli.instance_variable_get(:@git)
          expect(git).not_to receive(:tag_annotated)
          expect(local_cli).to receive(:run_cmd!).with("gem push #{gem_path}")
          expect(local_cli).to receive(:run_release_availability_probe) do |candidate|
            expect(candidate.published).to be(true)
            true
          end

          local_cli.send(:release_gem_and_tag_locally!, "1.2.3")
        end
      end

      it "preserves hyphenated gem names when deriving the published gem name" do
        local_cli = described_class.new

        expect(local_cli.send(:gem_name_from_gem_path, "pkg/my-gem-1.2.3.gem", "1.2.3")).to eq("my-gem")
      end

      it "does not clean up a candidate once registry availability has been validated" do
        local_cli = described_class.new
        candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
          gem_name: "mygem",
          version: "1.2.3",
          installed_before: false,
          published: false
        )

        expect(local_cli).to receive(:run_release_availability_probe).with(candidate).and_return(true)
        expect(local_cli.send(:confirm_release_candidate_available!, candidate)).to be(true)
        expect(candidate.published).to be(true)
      end

      it "validates availability with the shared Bundler inline source probe sourced from gem.coop" do
        local_cli = described_class.new
        candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
          gem_name: "mygem",
          version: "1.2.3",
          installed_before: false,
          published: false
        )

        script = local_cli.send(:release_availability_probe_script, candidate)

        expect(script).to include("require \"bundler/inline\"")
        expect(script).to include("source \"https://gem.coop\"")
        expect(script).to include("gem gem_name, \"= \#{version}\", require: false")
        expect(script).to include("Gem::Specification.find_all_by_name")
        expect(script).not_to include("Bundler.load")
        expect(script).not_to include("Gem.loaded_specs")
      end

      it "retries the gem.coop availability probe until the release resolves" do
        Dir.mktmpdir do |root|
          local_cli = described_class.new
          candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
            gem_name: "mygem",
            version: "1.2.3",
            installed_before: false,
            published: false
          )
          script_path = File.join(root, "probe.rb")
          File.write(script_path, "probe")
          failed = instance_double(Process::Status, success?: false, exitstatus: 1)
          passed = instance_double(Process::Status, success?: true, exitstatus: 0)

          allow(local_cli).to receive(:write_release_availability_probe).with(candidate).and_return(script_path)
          allow(local_cli).to receive(:release_availability_probe_attempts).and_return(3)
          allow(local_cli).to receive(:release_availability_probe_initial_delay).and_return(5)
          allow(local_cli).to receive(:release_availability_probe_interval).and_return(0)
          expect(local_cli).to receive(:sleep).with(5).ordered
          expect(Open3).to receive(:capture3).ordered.and_return(["", "missing", failed])
          expect(local_cli).to receive(:sleep).with(0).ordered
          expect(Open3).to receive(:capture3).ordered.and_return(["validated\n", "", passed])

          expect { expect(local_cli.send(:run_release_availability_probe, candidate)).to be(true) }
            .to output(/attempt 1\/3.*attempt 2\/3.*validated/m).to_stdout
        end
      end

      it "fails the gem.coop availability probe only after retry exhaustion" do
        Dir.mktmpdir do |root|
          local_cli = described_class.new
          candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
            gem_name: "mygem",
            version: "1.2.3",
            installed_before: false,
            published: false
          )
          script_path = File.join(root, "probe.rb")
          File.write(script_path, "probe")
          failed = instance_double(Process::Status, success?: false, exitstatus: 1)

          allow(local_cli).to receive(:write_release_availability_probe).with(candidate).and_return(script_path)
          allow(local_cli).to receive(:release_availability_probe_attempts).and_return(2)
          allow(local_cli).to receive(:release_availability_probe_initial_delay).and_return(5)
          allow(local_cli).to receive(:release_availability_probe_interval).and_return(0)
          expect(local_cli).to receive(:sleep).with(5).ordered
          expect(Open3).to receive(:capture3).ordered.and_return(["", "still missing", failed])
          expect(local_cli).to receive(:sleep).with(0).ordered
          expect(Open3).to receive(:capture3).ordered.and_return(["", "still missing", failed])

          expect do
            local_cli.send(:run_release_availability_probe, candidate)
          end.to raise_error(MockSystemExit, /after 2 attempt\(s\).*still missing/m)
        end
      end

      it "uninstalls a newly installed local candidate when registry availability cannot be validated" do
        local_cli = described_class.new
        candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
          gem_name: "mygem",
          version: "1.2.3",
          installed_before: false,
          published: false
        )
        local_cli.instance_variable_set(:@release_candidate, candidate)

        allow(local_cli).to receive(:gem_version_installed?).with("mygem", "1.2.3").and_return(true)
        expect(local_cli).to receive(:run_cmd!).with("gem uninstall mygem -v 1.2.3 -x -I --ignore-dependencies")

        expect do
          local_cli.send(:with_unpublished_candidate_cleanup) { raise(MockSystemExit, "publish failed") }
        end.to raise_error(MockSystemExit, /publish failed/)
      end

      it "does not uninstall a candidate after the gem push succeeds" do
        local_cli = described_class.new
        candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
          gem_name: "mygem",
          version: "1.2.3",
          installed_before: false,
          published: true
        )
        local_cli.instance_variable_set(:@release_candidate, candidate)

        expect(local_cli).not_to receive(:run_cmd!).with(/gem uninstall/)

        expect do
          local_cli.send(:with_unpublished_candidate_cleanup) { raise(MockSystemExit, "probe failed") }
        end.to raise_error(MockSystemExit, /probe failed/)
      end

      it "does not uninstall a candidate that was already installed before the release attempt" do
        local_cli = described_class.new
        candidate = Kettle::Dev::ReleaseCLI::ReleaseCandidate.new(
          gem_name: "mygem",
          version: "1.2.3",
          installed_before: true,
          published: false
        )
        local_cli.instance_variable_set(:@release_candidate, candidate)

        expect(local_cli).not_to receive(:run_cmd!).with(/gem uninstall/)

        expect do
          local_cli.send(:with_unpublished_candidate_cleanup) { raise(MockSystemExit, "publish failed") }
        end.to raise_error(MockSystemExit, /publish failed/)
      end
    end

    describe "push_tags!" do
      it "pushes tags only to 'all' when present" do
        allow(cli).to receive(:has_remote?).with("all").and_return(true)
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push_tags).with("all")
        cli.send(:push_tags!)
      end

      it "pushes tags to each remote when 'all' missing" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        allow(cli).to receive(:list_remotes).and_return(%w[origin github]) # includes two remotes
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push_tags).with("origin")
        expect(git).to receive(:push_tags).with("github")
        cli.send(:push_tags!)
      end

      it "pushes tags without specifying remote when no remotes configured" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        allow(cli).to receive(:list_remotes).and_return([])
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:push_tags).with(nil)
        cli.send(:push_tags!)
      end
    end

    describe "direct git wrappers" do
      it "runs checkout! and pull! via GitAdapter" do
        git = cli.instance_variable_get(:@git)
        expect(git).to receive(:checkout).with("main").and_return(true)
        cli.send(:checkout!, "main")
        expect(git).to receive(:pull).with("origin", "main").and_return(true)
        cli.send(:pull!, "main")
      end

      it "returns current_branch and lists remotes via GitAdapter" do
        git = cli.instance_variable_get(:@git)
        allow(git).to receive(:current_branch).and_return("feat")
        expect(cli.send(:current_branch)).to eq("feat")
        allow(git).to receive(:remotes).and_return(%w[origin github])
        expect(cli.send(:list_remotes)).to include("origin", "github")
      end

      it "fetches remote_url and prefers origin when appropriate via GitAdapter" do
        git = cli.instance_variable_get(:@git)
        allow(git).to receive(:remotes_with_urls).and_return({"origin" => "https://github.com/me/repo.git"})
        expect(cli.send(:remote_url, "origin")).to include("github.com")
        expect(cli.send(:preferred_github_remote)).to eq("origin")
      end

      it "checks remote presence (list_remotes) still works" do
        allow(cli).to receive(:list_remotes).and_return(["origin"])
        expect(cli.send(:has_remote?, "origin")).to be true
        expect(cli.send(:has_remote?, "github")).to be false
      end
    end

    describe "ensure_trunk_synced_before_push! divergence reconciliation" do
      around do |ex|
        orig_stdin = $stdin
        begin
          ex.run
        ensure
          $stdin = orig_stdin
        end
      end

      it "rebases when user selects r" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([1, 1])
        expect(cli).to receive(:checkout!).with("main").at_least(:once)
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("r\n")
        expect(cli).to receive(:run_cmd!).with("git rebase github/main")
        expect(cli).to receive(:run_cmd!).with("git push origin main")
        cli.send(:ensure_trunk_synced_before_push!, "main", "feat")
      end

      it "merges when user selects m" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([1, 1])
        expect(cli).to receive(:checkout!).with("main").at_least(:once)
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("m\n")
        expect(cli).to receive(:run_cmd!).with("git merge --no-ff github/main")
        expect(cli).to receive(:run_cmd!).with("git push origin main")
        expect(cli).to receive(:run_cmd!).with("git push github main")
        cli.send(:ensure_trunk_synced_before_push!, "main", "feat")
      end

      it "aborts when user selects a (abort)" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([1, 1])
        expect(cli).to receive(:checkout!).with("main").at_least(:once)
        expect(cli).to receive(:run_cmd!).with("git pull --rebase origin main")
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("a\n")
        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.to raise_error(MockSystemExit, /Aborted by user/)
      end

      it "returns early when origin and github trunks are in sync" do
        allow(cli).to receive(:has_remote?).with("all").and_return(false)
        expect(cli).to receive(:run_cmd!).with("git fetch origin main")
        allow(cli).to receive(:trunk_behind_remote?).and_return(false)
        allow(cli).to receive(:preferred_github_remote).and_return("github")
        expect(cli).to receive(:run_cmd!).with("git fetch github main")
        allow(cli).to receive(:ahead_behind_counts).with("origin/main", "github/main").and_return([0, 0])
        expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.not_to raise_error
      end
    end

    describe "#validate_checksums! error cases" do
      it "aborts when built gem cannot be found" do
        allow(cli).to receive(:gem_file_for_version).with("0.0.1").and_return(nil)
        expect { cli.send(:validate_checksums!, "0.0.1", stage: "stage") }.to raise_error(MockSystemExit, /Unable to locate built gem/)
      end

      it "aborts when checksum file is missing" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          other = described_class.new
          # create gem in pkg
          pkg = File.join(root, "pkg")
          FileUtils.mkdir_p(pkg)
          gem_file = File.join(pkg, "mygem-0.1.0.gem")
          File.write(gem_file, "data")
          expect { other.send(:validate_checksums!, "0.1.0", stage: "stage") }.to raise_error(MockSystemExit, /Expected checksum file not found/)
        end
      end
    end

    describe "#compute_sha256 shasum path" do
      it "uses shasum when available" do
        Dir.mktmpdir do |root|
          file = File.join(root, "f.bin")
          File.binwrite(file, "xyz")
          allow(cli).to receive(:system).with("which sha256sum > /dev/null 2>&1").and_return(false)
          allow(cli).to receive(:system).with("which shasum > /dev/null 2>&1").and_return(true)
          allow(Open3).to receive(:capture2e).with("shasum", "-a", "256", file).and_return(["abc123 #{file}", instance_double(Process::Status)])
          expect(cli.send(:compute_sha256, file)).to eq("abc123")
        end
      end
    end

    describe "#monitor_workflows_after_push! gitlab loop nil then success" do
      it "sleeps when pipeline initially missing then proceeds" do
        allow(ci_helpers).to receive(:project_root).and_return(Dir.pwd)
        allow(ci_helpers).to receive(:current_branch).and_return("feat")
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return(nil)
        allow(ci_helpers).to receive(:workflows_list).and_return([])
        allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        allow(ci_helpers).to receive(:repo_info_gitlab).and_return(%w[me repo])
        # first returns nil, then a success
        allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(nil, {"web_url" => "http://gitlab/pipeline"})
        allow(ci_helpers).to receive(:gitlab_success?).and_return(true)
        allow(ci_helpers).to receive(:gitlab_failed?).and_return(false)
        allow(cli).to receive(:ensure_github_pull_request_for_ci!)
        expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
      end
    end

    describe "start_step skipping" do
      it "skips initial steps when start_step is 10 (CI validation)", :jruby_head_release_flow do
        allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(false)
        # Ensure optional GitHub release (step 17) is a no-op to avoid real HTTP
        stub_env("GITHUB_TOKEN" => nil)
        local_cli = described_class.new(start_step: 10)
        allow(local_cli).to receive(:detect_version).and_return("2.2.22")
        stub_checksum_artifact(local_cli, "2.2.22", "kettle-dev")
        allow(local_cli).to receive(:ensure_bundler_2_7_plus!)
        # Spy on run_cmd! to ensure early commands are not invoked
        allow(local_cli).to receive(:run_cmd!)
        # Prevent later phases from doing real work
        allow(local_cli).to receive(:monitor_workflows_after_push!)
        allow(local_cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(local_cli).to receive(:checkout!)
        allow(local_cli).to receive(:pull!)
        allow(local_cli).to receive(:ensure_signing_setup_or_skip!)
        allow(local_cli).to receive(:validate_checksums!)
        allow(local_cli).to receive(:push_tags!)
        allow(local_cli).to receive(:detect_trunk_branch).and_return("main")
        allow(local_cli).to receive(:current_branch).and_return("feat")
        allow(local_cli).to receive(:confirm_release_candidate_available!)

        expect { local_cli.run }.not_to raise_error

        expect(local_cli).not_to have_received(:run_cmd!).with("bin/setup")
        expect(local_cli).not_to have_received(:run_cmd!).with("bin/rake")
        expect(local_cli).not_to have_received(:run_cmd!).with("bin/rake appraisal:generate")
      end

      it "skips selected numbered steps while running later steps", :jruby_head_release_flow do
        allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(false)
        stub_env("GITHUB_TOKEN" => nil)
        local_cli = described_class.new(start_step: 10, skip_steps: "10")
        allow(local_cli).to receive(:detect_version).and_return("1.2.3")
        allow(local_cli).to receive(:detect_gem_name).and_return("example")
        stub_checksum_artifact(local_cli, "1.2.3", "example")
        allow(local_cli).to receive(:detect_trunk_branch).and_return("main")
        allow(local_cli).to receive(:current_branch).and_return("feat")
        allow(local_cli).to receive(:ensure_bundler_2_7_plus!)
        allow(local_cli).to receive(:monitor_workflows_after_push!)
        allow(local_cli).to receive(:merge_feature_into_trunk_and_push!)
        allow(local_cli).to receive(:checkout!)
        allow(local_cli).to receive(:pull!)
        allow(local_cli).to receive(:ensure_signing_setup_or_skip!)
        allow(local_cli).to receive(:run_cmd!)
        allow(local_cli).to receive(:validate_checksums!)
        allow(local_cli).to receive(:push_tags!)
        allow(local_cli).to receive(:confirm_release_candidate_available!)

        expect { local_cli.run }.not_to raise_error

        expect(local_cli).not_to have_received(:monitor_workflows_after_push!)
        expect(local_cli).to have_received(:merge_feature_into_trunk_and_push!).with("main", "feat")
        expect(local_cli).to have_received(:run_cmd!).with("bundle exec rake build")
      end

      it "rejects invalid skip step values" do
        expect { described_class.new(skip_steps: "10,nope") }
          .to raise_error(MockSystemExit, /Invalid skip_steps value "nope"/)
      end
    end

    describe "RUBOCOP_LTS_LOCAL release preflight" do
      it "switches the local RuboCop-LTS checkout to the selected wrapper branch" do
        Dir.mktmpdir do |root|
          write_style_local(root, "rubocop-ruby2_4")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          git = instance_double(Kettle::Dev::GitAdapter)
          local_cli.instance_variable_set(:@git, git)
          checkout = File.join("/workspace/rubocop-lts", "rubocop-lts")
          stub_env("RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts")

          expect(git).to receive(:capture)
            .with(["-C", checkout, "branch", "--show-current"])
            .and_return(["r1_8-even-v0", true])
          expect(git).to receive(:capture)
            .with(["-C", checkout, "switch", "r2_4-even-v12"])
            .and_return(["", true])

          expect { local_cli.send(:prepare_rubocop_lts_local_branch!) }.not_to raise_error
        end
      end

      it "does not switch when the local RuboCop-LTS checkout is already on the selected branch" do
        Dir.mktmpdir do |root|
          write_style_local(root, "rubocop-ruby3_2")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          git = instance_double(Kettle::Dev::GitAdapter)
          local_cli.instance_variable_set(:@git, git)
          checkout = File.join("/workspace/rubocop-lts", "rubocop-lts")
          stub_env("RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts")

          expect(git).to receive(:capture)
            .with(["-C", checkout, "branch", "--show-current"])
            .and_return(["r3_2-even-v24", true])
          expect(git).not_to receive(:capture).with(["-C", checkout, "switch", anything])

          expect { local_cli.send(:prepare_rubocop_lts_local_branch!) }.not_to raise_error
        end
      end

      it "does not switch an active local branch-stack checkout when releasing that checkout" do
        Dir.mktmpdir do |workspace|
          root = File.join(workspace, "rubocop-lts")
          FileUtils.mkdir_p(root)
          File.write(File.join(root, ".kettle-family.yml"), <<~YAML)
            release:
              target_branches:
                - r1_8-even-v0
          YAML
          write_style_local(root, "rubocop-ruby3_2")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          git = instance_double(Kettle::Dev::GitAdapter)
          local_cli.instance_variable_set(:@git, git)
          stub_env("RUBOCOP_LTS_LOCAL" => workspace)

          expect(git).not_to receive(:capture)

          expect { local_cli.send(:prepare_rubocop_lts_local_branch!) }.not_to raise_error
        end
      end

      it "still switches a same-family local checkout when it is not a branch-stack release checkout" do
        Dir.mktmpdir do |workspace|
          root = File.join(workspace, "rubocop-lts")
          FileUtils.mkdir_p(root)
          write_style_local(root, "rubocop-ruby3_2")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          git = instance_double(Kettle::Dev::GitAdapter)
          local_cli.instance_variable_set(:@git, git)
          stub_env("RUBOCOP_LTS_LOCAL" => workspace)

          expect(git).to receive(:capture)
            .with(["-C", root, "branch", "--show-current"])
            .and_return(["main", true])
          expect(git).to receive(:capture)
            .with(["-C", root, "switch", "r3_2-even-v24"])
            .and_return(["", true])

          expect { local_cli.send(:prepare_rubocop_lts_local_branch!) }.not_to raise_error
        end
      end

      it "aborts when the local RuboCop-LTS checkout cannot switch branches" do
        Dir.mktmpdir do |root|
          write_style_local(root, "rubocop-ruby2_4")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          git = instance_double(Kettle::Dev::GitAdapter)
          local_cli.instance_variable_set(:@git, git)
          checkout = File.join("/workspace/rubocop-lts", "rubocop-lts")
          stub_env("RUBOCOP_LTS_LOCAL" => "/workspace/rubocop-lts")

          allow(git).to receive(:capture)
            .with(["-C", checkout, "branch", "--show-current"])
            .and_return(["r1_8-even-v0", true])
          allow(git).to receive(:capture)
            .with(["-C", checkout, "switch", "r2_4-even-v12"])
            .and_return(["", false])

          expect { local_cli.send(:prepare_rubocop_lts_local_branch!) }
            .to raise_error(MockSystemExit, /Cannot switch RUBOCOP_LTS_LOCAL checkout/)
        end
      end
    end

    describe "#update_rakefile_example_header!" do
      it "updates header line to current version and date when file exists", freeze: Time.local(2025, 8, 29) do
        Dir.mktmpdir do |root|
          # Arrange Rakefile.example with an older header and some content
          body = <<~RB
            # frozen_string_literal: true

            # kettle-dev Rakefile v0.9.0 - 2024-12-31
            puts "Hello"
          RB
          File.write(File.join(root, "Rakefile.example"), body)
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new

          local_cli.send(:update_rakefile_example_header!, "1.2.3")

          updated = File.read(File.join(root, "Rakefile.example"))
          expect(updated).to include("# kettle-dev Rakefile v1.2.3 - 2025-08-29")
          expect(updated).to include("# frozen_string_literal: true")
          expect(updated).to include("puts \"Hello\"")
        end
      end

      it "is a no-op when file is missing" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          expect { local_cli.send(:update_rakefile_example_header!, "1.2.3") }.not_to raise_error
        end
      end
    end

    describe "regression: Rakefile.example header uses version.rb even if RubyGems.org has higher overall" do
      it "injects the version from version.rb (e.g., 1.0.15) and not a higher 1.2.x from RubyGems.org", freeze: Time.new(2015, 12, 28, 13, 14, 15) do
        Dir.mktmpdir do |root|
          # Prepare a Rakefile.example with an outdated header
          File.write(File.join(root, "Rakefile.example"), <<~RB)
            # frozen_string_literal: true

            # kettle-dev Rakefile v0.0.0 - 2000-01-01
            puts "Hello"
          RB

          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new(start_step: 2)

          # Force detect_version to desired next version and make RubyGems.org suggest a higher overall
          allow(cli).to receive(:detect_version).and_return("1.0.15")
          allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
          stub_checksum_artifact(cli, "1.0.15", "kettle-dev")
          allow(cli).to receive(:latest_released_versions).and_return(%w[1.2.10 1.2.10]) # overall and series
          allow(cli).to receive(:validate_copyright_years!)
          allow(cli).to receive(:update_readme_kloc_badge!)

          # Auto-confirm the prompt
          allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")

          # Stub out subsequent steps so we only execute step 2
          allow(cli).to receive(:run_cmd!)
          allow(cli).to receive(:validate_checksums!)
          allow(cli).to receive(:maybe_run_local_ci_before_push!)
          allow(cli).to receive(:ensure_bundler_2_7_plus!)
          allow(cli).to receive(:monitor_workflows_after_push!)
          allow(cli).to receive(:merge_feature_into_trunk_and_push!)
          allow(cli).to receive(:checkout!)
          allow(cli).to receive(:pull!)
          allow(cli).to receive(:ensure_signing_setup_or_skip!)
          allow(cli).to receive(:push_tags!)
          allow(cli).to receive(:detect_trunk_branch).and_return("main")
          allow(cli).to receive(:current_branch).and_return("feat")
          allow(cli).to receive(:confirm_release_candidate_available!)

          # Execute run starting at step 2 to cover header update path
          expect { cli.run }.not_to raise_error

          updated = File.read(File.join(root, "Rakefile.example"))
          expect(updated).to include("# kettle-dev Rakefile v1.0.15 - 2015-12-28")
          expect(updated).to include("puts \"Hello\"")
        end
      end
    end

    describe "update_readme_kloc_badge! and helpers" do
      it "updates README and README.example KLOC values based on CHANGELOG denominator", :check_output do
        Dir.mktmpdir do |root|
          # Prepare files
          FileUtils.mkdir_p(File.join(root, ".github", "workflows"))
          version = "9.9.9"
          changelog = <<~MD
            ## [#{version}] - 2025-08-28
            - COVERAGE: 97.70% -- 2125/2175 lines in 20 files
          MD
          File.write(File.join(root, "CHANGELOG.md"), changelog)
          readme = <<~MD
            [🧮kloc-img]: https://img.shields.io/badge/KLOC-0.000-FFDD67.svg?style=flat
          MD
          File.write(File.join(root, "README.md"), readme)
          File.write(File.join(root, "README.md.example"), readme)

          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          allow(cli).to receive(:detect_version).and_return(version)
          allow(cli).to receive(:validate_copyright_years!)
          allow(cli).to receive(:update_rakefile_example_header!)

          expect { cli.send(:update_readme_kloc_badge!) }.not_to raise_error
          updated = File.read(File.join(root, "README.md"))
          updated_ex = File.read(File.join(root, "README.md.example"))
          # 2175 / 1000.0 => 2.175
          expect(updated).to include("KLOC-2.175-")
          expect(updated_ex).to include("KLOC-2.175-")
        end
      end

      it "skips when README.example missing and avoids rewriting when no change", :check_output do
        Dir.mktmpdir do |root|
          version = "9.9.8"
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            ## [#{version}]
            - COVERAGE: 10.00% -- 100/1000 lines in 2 files
          MD
          orig = "[🧮kloc-img]: https://img.shields.io/badge/KLOC-1.000-FFDD67.svg?style=flat\n"
          File.write(File.join(root, "README.md"), orig)
          # No README.md.example
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          allow(cli).to receive(:detect_version).and_return(version)
          cli.send(:update_readme_kloc_badge!)
          # unchanged KLOC remains 1.000 so file should be untouched
          expect(File.read(File.join(root, "README.md"))).to eq(orig)
        end
      end
    end

    describe "copyright helpers edge cases" do
      it "extracts years from descending range by swapping endpoints" do
        Dir.mktmpdir do |root|
          path = File.join(root, "LICENSE.txt")
          File.write(path, "Copyright 2025-2023 Example")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          years = cli.send(:extract_years_from_file, path)
          expect(years.to_a).to include(2023, 2024, 2025)
        end
      end

      it "collapses with trailing segment flush" do
        cli = described_class.new
        str = cli.send(:collapse_years, [2020, 2021, 2023])
        expect(str).to eq("2020-2021, 2023")
      end

      it "injects nothing when no year blob present" do
        Dir.mktmpdir do |root|
          path = File.join(root, "README.md")
          content = "Some text with Copyright notice but no years present."
          File.write(path, content)
          cli = described_class.new
          expect { cli.send(:inject_years_into_file!, path, Set.new([2020, 2021])) }.not_to raise_error
          expect(File.read(path)).to eq(content)
        end
      end

      # NOTE: Additional edge coverage for reformat is exercised indirectly by other specs.
    end

    describe "CHANGELOG and GitHub release helpers" do
      it "extract_changelog_for_version rescues parser errors" do
        Dir.mktmpdir do |root|
          allow(ci_helpers).to receive(:project_root).and_return(root)
          path = File.join(root, "CHANGELOG.md")
          File.write(path, "## [1.2.3]\n")
          cli = described_class.new
          # Force File.read to blow up to hit rescue
          allow(File).to receive(:read).with(path).and_raise(ArgumentError, "boom")
          section, a, b = cli.send(:extract_changelog_for_version, "1.2.3")
          expect(section).to be_nil
          expect(a).to be_nil
          expect(b).to be_nil
        end
      end

      it "github_create_release returns success on HTTPSuccess/Created and rescues exceptions" do
        cli = described_class.new
        # Success path
        success_res = Net::HTTPCreated.new("1.1", "201", "Created")
        http_double = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(http_double)
        allow(http_double).to receive(:request).and_return(success_res)
        ok, msg = cli.send(:github_create_release, owner: "me", repo: "r", token: "t", tag: "v1.0.0", title: "v1.0.0", body: "hi")
        expect(ok).to be(true)
        expect(msg).to eq("created")

        # Exception path
        allow(Net::HTTP).to receive(:start).and_raise(Timeout::Error, "timeout")
        ok2, msg2 = cli.send(:github_create_release, owner: "me", repo: "r", token: "t", tag: "v1.0.0", title: "v1.0.0", body: "hi")
        expect(ok2).to be(false)
        expect(msg2).to include("Timeout::Error")
      end
    end
  end

  # rubocop:enable RSpec/ReceiveMessages, RSpec/StubbedMock

  # Consolidated from release_cli_github_spec.rb and release_cli_github_footer_spec.rb and release_cli_copyright_spec.rb
  describe "GitHub release behaviors" do
    let(:ci_helpers) { Kettle::Dev::CIHelpers }

    describe "GitHub release creation" do
      it "skips when token present but CHANGELOG has no matching section" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n\n")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          allow(local_cli).to receive(:preferred_github_remote).and_return("origin")
          allow(local_cli).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
          stub_env("GITHUB_TOKEN" => "tok")
          expect { local_cli.send(:maybe_create_github_release!, "9.9.9") }.not_to raise_error
        end
      end

      it "skips when GITHUB_TOKEN is missing" do
        stub_env("GITHUB_TOKEN" => nil)
        expect { described_class.new.send(:maybe_create_github_release!, "1.2.3") }.not_to raise_error
      end

      it "creates a release with title and body from CHANGELOG when token present", :aggregate_failures do
        Dir.mktmpdir do |root|
          # Minimal CHANGELOG with a section and links
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            # Changelog

            ## [Unreleased]

            ## [1.2.3] - 2025-08-28
            - TAG: [v1.2.3][1.2.3t]
            - Added
              - Feature X

            [Unreleased]: https://github.com/me/repo/compare/v1.2.3...HEAD
            [1.2.3]: https://github.com/me/repo/compare/v1.2.2...v1.2.3
            [1.2.3t]: https://github.com/me/repo/releases/tag/v1.2.3
          MD
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new

          # Simulate GitHub remote
          allow(local_cli).to receive(:preferred_github_remote).and_return("origin")
          allow(local_cli).to receive(:remote_url).with("origin").and_return("https://github.com/me/repo.git")

          # Stub env and Net::HTTP
          stub_env("GITHUB_TOKEN" => "token123")

          response = instance_double(Net::HTTPCreated)
          allow(response).to receive_messages(code: "201", body: "{\"id\":1}")

          http = instance_double(Net::HTTP)
          allow(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(response)

          allow(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

          expect { local_cli.send(:maybe_create_github_release!, "1.2.3") }.not_to raise_error
          expect(http).to have_received(:request).with(instance_of(Net::HTTP::Post))
          expect(Net::HTTP).to have_received(:start).with("api.github.com", 443, use_ssl: true)
        end
      end

      it "treats 422 already_exists as success", :aggregate_failures do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            # Changelog

            ## [Unreleased]

            ## [2.0.0] - 2025-08-28
            - TAG: [v2.0.0][2.0.0t]

            [Unreleased]: https://github.com/me/repo/compare/v2.0.0...HEAD
            [2.0.0]: https://github.com/me/repo/compare/v1.9.9...v2.0.0
            [2.0.0t]: https://github.com/me/repo/releases/tag/v2.0.0
          MD
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          allow(local_cli).to receive(:preferred_github_remote).and_return("origin")
          allow(local_cli).to receive(:remote_url).with("origin").and_return("https://github.com/me/repo")
          stub_env("GITHUB_TOKEN" => "token123")

          resp = instance_double(Net::HTTPUnprocessableEntity)
          allow(resp).to receive_messages(code: "422", body: "{\"errors\":[{\"code\":\"already_exists\"}]}")

          http = instance_double(Net::HTTP)
          allow(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(resp)
          allow(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

          expect { local_cli.send(:maybe_create_github_release!, "2.0.0") }.not_to raise_error
          expect(http).to have_received(:request).with(instance_of(Net::HTTP::Post))
          expect(Net::HTTP).to have_received(:start).with("api.github.com", 443, use_ssl: true)
        end
      end

      it "uses origin when preferred remote is nil", :aggregate_failures do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            # Changelog

            ## [Unreleased]

            ## [3.0.0] - 2025-08-28
            - TAG: [v3.0.0][3.0.0t]

            [Unreleased]: https://github.com/me/repo/compare/v3.0.0...HEAD
            [3.0.0]: https://github.com/me/repo/compare/v2.9.9...v3.0.0
            [3.0.0t]: https://github.com/me/repo/releases/tag/v3.0.0
          MD
          allow(ci_helpers).to receive(:project_root).and_return(root)
          local_cli = described_class.new
          allow(local_cli).to receive(:preferred_github_remote).and_return(nil)
          allow(local_cli).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
          stub_env("GITHUB_TOKEN" => "tok")

          response = instance_double(Net::HTTPInternalServerError)
          allow(response).to receive_messages(code: "500", body: "oops")
          http = instance_double(Net::HTTP)
          allow(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(response)
          allow(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

          expect { local_cli.send(:maybe_create_github_release!, "3.0.0") }.not_to raise_error
          expect(http).to have_received(:request).with(instance_of(Net::HTTP::Post))
          expect(Net::HTTP).to have_received(:start).with("api.github.com", 443, use_ssl: true)
        end
      end

      it "warns and skips when owner/repo cannot be determined" do
        stub_env("GITHUB_TOKEN" => "secret")
        cli = described_class.new
        allow(cli).to receive_messages(preferred_github_remote: nil, remote_url: "ssh://gitlab.com/user/repo")
        expect { cli.send(:maybe_create_github_release!, "1.0.0") }.not_to raise_error
      end
    end

    describe "release notes footer from FUNDING.md" do
      it "appends footer from FUNDING.md between tags with a leading blank line", :aggregate_failures do
        Dir.mktmpdir do |root|
          # CHANGELOG with basic section and links
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            # Changelog

            ## [1.0.0] - 2025-08-29
            - TAG: [v1.0.0][1.0.0t]

            [1.0.0]: https://github.com/me/repo/compare/v0.9.9...v1.0.0
            [1.0.0t]: https://github.com/me/repo/releases/tag/v1.0.0
          MD

          # FUNDING with markers
          File.write(File.join(root, "FUNDING.md"), <<~MD)
            <!-- RELEASE-NOTES-FOOTER-START -->

            Support the project ❤️

            [Sponsor](https://github.com/sponsors/me)
            <!-- RELEASE-NOTES-FOOTER-END -->
          MD

          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          allow(cli).to receive(:preferred_github_remote).and_return("origin")
          allow(cli).to receive(:remote_url).with("origin").and_return("https://github.com/me/repo")
          stub_env("GITHUB_TOKEN" => "tok")

          # Capture the body sent to GitHub
          captured_body = nil
          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)
          allow(http).to receive(:request) do |req|
            payload = JSON.parse(req.body)
            captured_body = payload["body"]
            instance_double(Net::HTTPCreated, code: "201", body: "{}")
          end

          expect { cli.send(:maybe_create_github_release!, "1.0.0") }.not_to raise_error

          # Verify footer appended and preceded by a single blank line
          expect(captured_body).to include("[1.0.0t]: https://github.com/me/repo/releases/tag/v1.0.0")
          expect(captured_body).to match(/\n\n\[1.0.0\]: .*\n\[1.0.0t\]: .*\n\nSupport the project/m)
          # Ensure the footer content itself does not include the HTML markers
          expect(captured_body).not_to include("RELEASE-NOTES-FOOTER-START")
          expect(captured_body).not_to include("RELEASE-NOTES-FOOTER-END")
        end
      end

      it "handles missing FUNDING.md gracefully" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "CHANGELOG.md"), <<~MD)
            ## [1.2.3]
            [1.2.3]: url
            [1.2.3t]: url
          MD
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          allow(cli).to receive(:preferred_github_remote).and_return("origin")
          allow(cli).to receive(:remote_url).with("origin").and_return("https://github.com/me/repo")
          stub_env("GITHUB_TOKEN" => "tok")

          http = instance_double(Net::HTTP)
          allow(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)
          allow(http).to receive(:request).and_return(instance_double(Net::HTTPCreated, code: "201", body: "{}"))

          expect { cli.send(:maybe_create_github_release!, "1.2.3") }.not_to raise_error
        end
      end
    end

    describe "copyright years validation" do
      it "passes when README.md and LICENSE.txt have identical year sets and include current year" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "README.md"), <<~MD)
            # Title

            ### © Copyright

            Copyright (c) 2023-2025 Example
          MD
          File.write(File.join(root, "LICENSE.txt"), <<~MD)
            The MIT License (MIT)

            Copyright (c) 2023, 2024, 2025 Example
          MD
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        end
      end

      it "rewrites consecutive years into a range in both files", :aggregate_failures, freeze: Time.local(2026, 7, 21) do
        Dir.mktmpdir do |root|
          # Build a list of consecutive years ending at the frozen current year
          # so validate_copyright_years! only reformats (no injection needed).
          start_year = 2024
          years_list = (start_year..2026).to_a.join(", ")
          File.write(File.join(root, "README.md"), "Copyright (c) #{years_list} Example")
          File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) #{years_list} Example")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          expect { cli.send(:validate_copyright_years!) }.not_to raise_error
          expect(File.read(File.join(root, "README.md"))).to include("#{start_year}-2026")
          expect(File.read(File.join(root, "LICENSE.txt"))).to include("#{start_year}-2026")
        end
      end

      it "aborts when sets differ (mismatch)" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "README.md"), "Copyright (c) 2023, 2025 Example\n")
          File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright 2023-2024 Example\n")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          expect { cli.send(:validate_copyright_years!) }.to raise_error(MockSystemExit, /Mismatched copyright years/)
        end
      end

      it "is skipped silently if either file is missing" do
        Dir.mktmpdir do |root|
          File.write(File.join(root, "README.md"), "Copyright (c) 2024")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        end
      end

      it "injects current year into both files when missing and sets match", :aggregate_failures, freeze: Time.local(2026, 7, 21) do
        Dir.mktmpdir do |root|
          last_year = 2025
          File.write(File.join(root, "README.md"), "Copyright (c) #{last_year} Example")
          File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) #{last_year} Example")
          allow(ci_helpers).to receive(:project_root).and_return(root)
          cli = described_class.new
          expect { cli.send(:validate_copyright_years!) }.not_to raise_error
          expect(File.read(File.join(root, "README.md"))).to include("#{last_year}-2026")
          expect(File.read(File.join(root, "LICENSE.txt"))).to include("#{last_year}-2026")
        end
      end
    end
  end
end
