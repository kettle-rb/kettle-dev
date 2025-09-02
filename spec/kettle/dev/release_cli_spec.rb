# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/StubbedMock, RSpec/ReceiveMessages

RSpec.describe Kettle::Dev::ReleaseCLI do
  let(:ci_helpers) { Kettle::Dev::CIHelpers }
  let(:cli) { described_class.new }

  before do
    # Speed up polling loops in CI monitor tests
    allow(cli).to receive(:sleep)
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

  describe "#run_cmd! (signing env injection)" do
    it "prefixes SKIP_GEM_SIGNING for 'bundle exec rake build' when env set" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "SKIP_GEM_SIGNING=true bundle exec rake build").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake build")
    end

    it "prefixes SKIP_GEM_SIGNING for 'bundle exec rake release' when env set" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "SKIP_GEM_SIGNING=true bundle exec rake release").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake release")
    end

    it "does not prefix when SKIP_GEM_SIGNING is not set" do
      # ensure var is not present
      stub_env("SKIP_GEM_SIGNING" => nil)
      expect(cli).to receive(:system).with(kind_of(Hash), "bundle exec rake build").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake build")
    end

    it "does not prefix unrelated commands" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "bin/rake").and_return(true)
      cli.send(:run_cmd!, "bin/rake")
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
      body = [
        {"number" => "1.2.3"},
        {"number" => "1.2.4.pre"},
        {"number" => "1.3.0"},
        {"number" => "2.0.0"},
        {"number" => "1.2.10"},
        {"number" => "1.2.9-alpha"},
      ].to_json
      resp = response_class.new(body)
      allow(Net::HTTP).to receive(:get_response).and_return(resp)
      overall, series = cli.send(:latest_released_versions, "gemx", "1.2.0")
      expect(overall).to eq("2.0.0")
      expect(series).to eq("1.2.10")
    end

    it "returns [nil, nil] on errors" do
      allow(Net::HTTP).to receive(:get_response).and_raise(StandardError)
      overall, series = cli.send(:latest_released_versions, "gemx", "1.2.3")
      expect(overall).to be_nil
      expect(series).to be_nil
    end
  end

  describe "latest_released_versions (integration with RubyGems via VCR)" do
    it "fetches real versions for kettle-dev and does not report a 1.2.x series", :check_output do
      # Use VCR to record once then replay. We avoid making any strong assertion on the exact
      # version numbers to keep the test resilient, but we do assert no 1.2.x appears for this gem.
      cassette = "rubygems_versions_kettle_dev"
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
      allow(cli).to receive(:run_cmd!).with("git add -A")
      allow(cli).to receive(:git_output).with(["status", "--porcelain"]).and_return(["", true])
      expect(cli.send(:commit_release_prep!, "1.0.0")).to be false
    end

    it "commits and returns true when there are changes" do
      allow(cli).to receive(:git_output).with(["status", "--porcelain"]).and_return([" M file", true])
      allow(cli).to receive(:run_cmd!).with("git add -A")
      expect(cli).to receive(:run_cmd!).with(/git commit -am/)
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
  end

  describe "git and system helpers" do
    it "detects trunk branch from origin remote output (still via git command)" do
      out = "Remote HEAD branch: main\n  HEAD branch: main\n"
      allow(cli).to receive(:git_output).with(["remote", "show", "origin"]).and_return([out, true])
      expect(cli.send(:detect_trunk_branch)).to eq("main")
    end

    it "parses remotes_with_urls and candidates" do
      git = cli.instance_variable_get(:@git)
      allow(git).to receive(:remotes_with_urls).and_return({
        "origin" => "git@github.com:me/repo.git",
        "github" => "https://github.com/me/repo.git",
        "gl" => "https://gitlab.com/me/repo",
        "cb" => "git@codeberg.org:me/repo.git",
      })
      urls = cli.send(:remotes_with_urls)
      expect(urls["origin"]).to include("github.com")
      expect(cli.send(:github_remote_candidates)).to include("origin", "github")
      expect(cli.send(:gitlab_remote_candidates)).to include("gl")
      expect(cli.send(:codeberg_remote_candidates)).to include("cb")
      expect(cli.send(:preferred_github_remote)).to eq("github")
    end

    it "parses github owner/repo from ssh and https and fails otherwise" do
      expect(cli.send(:parse_github_owner_repo, "git@github.com:user/repo.git")).to eq(["user", "repo"])
      expect(cli.send(:parse_github_owner_repo, "https://github.com/user/repo")).to eq(["user", "repo"])
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
      expect(cli).to receive(:run_cmd!).with("git fetch --all")
      allow(cli).to receive(:list_remotes).and_return(["all", "origin", "github"])
      allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
      allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 1])
      allow(cli).to receive(:remote_branch_exists?).with("github", "main").and_return(true)
      allow(cli).to receive(:ahead_behind_counts).with("main", "github/main").and_return([0, 0])
      expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.to raise_error(MockSystemExit, /missing commits present on: origin/)
    end

    it "reports parity when all remotes are synced" do
      allow(cli).to receive(:has_remote?).with("all").and_return(true)
      expect(cli).to receive(:run_cmd!).with("git fetch --all")
      allow(cli).to receive(:list_remotes).and_return(["all", "origin"])
      allow(cli).to receive(:remote_branch_exists?).with("origin", "main").and_return(true)
      allow(cli).to receive(:ahead_behind_counts).with("main", "origin/main").and_return([0, 0])
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
      allow(ci_helpers).to receive(:workflows_list).and_return(["ci.yml", "lint.yml"])
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      run1 = {"html_url" => "http://example/1"}
      run2 = {"html_url" => "http://example/2"}
      allow(ci_helpers).to receive(:latest_run).with(owner: "me", repo: "repo", workflow_file: "ci.yml", branch: "feat").and_return(run1)
      allow(ci_helpers).to receive(:latest_run).with(owner: "me", repo: "repo", workflow_file: "lint.yml", branch: "feat").and_return(run2)
      allow(ci_helpers).to receive(:success?).and_return(true)
      expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
    end

    it "aborts when a GitHub workflow fails" do
      allow(ci_helpers).to receive(:workflows_list).and_return(["ci.yml"])
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return([])
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
      allow(ci_helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])
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
      allow(ci_helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])
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
      allow(cli).to receive(:ensure_bundler_2_7_plus!) # skip real check
      allow(cli).to receive(:detect_version).and_return("1.2.3")
      allow(cli).to receive(:detect_gem_name).and_return("mygem")
      allow(cli).to receive(:latest_released_versions).and_return(["1.2.3", "1.2.3"]) # equal -> abort
      # First prompt will not be reached because we abort earlier
      expect { cli.run }.to raise_error(MockSystemExit, /version bump required/)
    end

    it "runs happy path when RubyGems is offline and Appraisals exist and SKIP_GEM_SIGNING is set" do
      # Make prompts auto-accept via input adapter
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")

      stub_env("SKIP_GEM_SIGNING" => "true")

      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("9.9.9")
      allow(cli).to receive(:detect_gem_name).and_return("mygem")
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
      expect(cli).to receive(:validate_checksums!).with("9.9.9", stage: "after build + gem_checksums")
      expect(cli).to receive(:validate_checksums!).with("9.9.9", stage: "after release")

      # Appraisals exists at repo root; ensure truthy branch executes
      expect { cli.run }.not_to raise_error

      # Ensure the initial build/release commands were attempted
      expect(cli).to have_received(:run_cmd!).with("bin/setup")
      expect(cli).to have_received(:run_cmd!).with("bin/rake")
      expect(cli).to have_received(:run_cmd!).with("bin/rake appraisal:update")
      expect(cli).to have_received(:run_cmd!).with("bundle exec rake build")
      expect(cli).to have_received(:run_cmd!).with("bin/gem_checksums")
      expect(cli).to have_received(:run_cmd!).with("bundle exec rake release")
    end

    it "skips appraisal:update when Appraisals file missing" do
      # Accept initial prompt via input adapter
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")

      stub_env("SKIP_GEM_SIGNING" => "true")

      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("9.9.9")
      allow(cli).to receive(:detect_gem_name).and_return("mygem")
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
      expect(cli).not_to have_received(:run_cmd!).with("bin/rake appraisal:update")
    end

    it "aborts when signing enabled on tty and user declines prompt" do
      allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(true)
      # Two prompts: first we answer 'y' to proceed, second we answer 'n' to abort signing
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n", "n\n")

      stub_env("SKIP_GEM_SIGNING" => nil, "CI" => "true")

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

    it "prints series info when latest overall is different series and continues" do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("1.2.10")
      allow(cli).to receive(:detect_gem_name).and_return("mygem")
      allow(cli).to receive(:latest_released_versions).and_return(["1.3.0", "1.2.9"]) # triggers line 36 and 47 branch
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
      expect { cli.run }.not_to raise_error
    end

    it "rescues failures from RubyGems check and proceeds to user prompt" do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("1.2.3")
      allow(cli).to receive(:detect_gem_name).and_raise(StandardError.new("boom"))
      expect { cli.run }.to raise_error(MockSystemExit, /please update version.rb/)
    end
  end

  describe "#run sanity-check branches" do
    it "aborts on downgrade when latest target is higher", :check_output do
      cli = described_class.new
      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("1.2.3")
      allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
      # overall is higher than current series; no series-specific latest -> target=nil would skip, so provide same-series higher
      allow(cli).to receive(:latest_released_versions).and_return(["1.2.4", "1.2.4"]) # [overall, for_series]
      expect do
        cli.run
      end.to raise_error(MockSystemExit, /version must be bumped above 1.2.4/)
    end

    it "prints offline message when target cannot be determined even though overall present", :check_output do
      cli = described_class.new
      allow(cli).to receive(:ensure_bundler_2_7_plus!)
      allow(cli).to receive(:detect_version).and_return("1.2.3")
      allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
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
      # Make final detection trivial
      allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")

      # Ensure the offline message was printed during run
      expect { cli.run }.to output(/Could not determine latest released version from RubyGems/).to_stdout
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
      allow(cli).to receive(:git_output).with(["config", "user.name"]).and_return(["Alice", true])
      allow(cli).to receive(:git_output).with(["config", "user.email"]).and_return(["alice@example.com", true])
      expect { cli.send(:ensure_git_user!) }.not_to raise_error
    end

    it "aborts when missing name or email" do
      allow(cli).to receive(:git_output).with(["config", "user.name"]).and_return(["", true])
      allow(cli).to receive(:git_output).with(["config", "user.email"]).and_return(["", false])
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
        expect(cli).to receive(:system).with("git", "reset", "--soft", "HEAD^")
        expect { cli.send(:maybe_run_local_ci_before_push!, true) }.to raise_error(MockSystemExit, /local CI failure/)
      end
    end
  end

  describe "push_tags!" do
    it "pushes tags only to 'all' when present" do
      allow(cli).to receive(:has_remote?).with("all").and_return(true)
      expect(cli).to receive(:run_cmd!).with("git push all --tags")
      cli.send(:push_tags!)
    end

    it "pushes tags to each remote when 'all' missing" do
      allow(cli).to receive(:has_remote?).with("all").and_return(false)
      allow(cli).to receive(:list_remotes).and_return(["origin", "github"]) # includes two remotes
      expect(cli).to receive(:run_cmd!).with("git push origin --tags")
      expect(cli).to receive(:run_cmd!).with("git push github --tags")
      cli.send(:push_tags!)
    end

    it "pushes tags without specifying remote when no remotes configured" do
      allow(cli).to receive(:has_remote?).with("all").and_return(false)
      allow(cli).to receive(:list_remotes).and_return([])
      expect(cli).to receive(:run_cmd!).with("git push --tags")
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
      allow(git).to receive(:remotes).and_return(["origin", "github"])
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
      allow(ci_helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])
      # first returns nil, then a success
      allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(nil, {"web_url" => "http://gitlab/pipeline"})
      allow(ci_helpers).to receive(:gitlab_success?).and_return(true)
      allow(ci_helpers).to receive(:gitlab_failed?).and_return(false)
      expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
    end
  end

  describe "start_step skipping" do
    it "skips initial steps when start_step is 10 (CI validation)" do
      allow(Kettle::Dev::InputAdapter).to receive(:tty?).and_return(false)
      local_cli = described_class.new(start_step: 10)
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

      expect { local_cli.run }.not_to raise_error

      expect(local_cli).not_to have_received(:run_cmd!).with("bin/setup")
      expect(local_cli).not_to have_received(:run_cmd!).with("bin/rake")
      expect(local_cli).not_to have_received(:run_cmd!).with("bin/rake appraisal:update")
    end
  end

  describe "#update_rakefile_example_header!" do
    it "updates header line to current version and date when file exists" do
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

        # Freeze time for deterministic date
        t = Time.local(2025, 8, 29)
        allow(Time).to receive(:now).and_return(t)

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

  describe "regression: Rakefile.example header uses version.rb even if RubyGems has higher overall" do
    it "injects the version from version.rb (e.g., 1.0.15) and not a higher 1.2.x from RubyGems", freeze: Time.new(2015, 12, 28, 13, 14, 15) do
      Dir.mktmpdir do |root|
        # Prepare a Rakefile.example with an outdated header
        File.write(File.join(root, "Rakefile.example"), <<~RB)
          # frozen_string_literal: true

          # kettle-dev Rakefile v0.0.0 - 2000-01-01
          puts "Hello"
        RB

        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new(start_step: 2)

        # Force detect_version to desired next version and make RubyGems suggest a higher overall
        allow(cli).to receive(:detect_version).and_return("1.0.15")
        allow(cli).to receive(:detect_gem_name).and_return("kettle-dev")
        allow(cli).to receive(:latest_released_versions).and_return(["1.2.10", "1.2.10"]) # overall and series
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
      expect(msg2).to match(/Timeout::Error/)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/StubbedMock, RSpec/ReceiveMessages


# Consolidated from release_cli_github_spec.rb and release_cli_github_footer_spec.rb and release_cli_copyright_spec.rb
RSpec.describe Kettle::Dev::ReleaseCLI do
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

    it "creates a release with title and body from CHANGELOG when token present" do
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
        allow(response).to receive(:code).and_return("201")
        allow(response).to receive(:body).and_return("{\"id\":1}")

        http = instance_double(Net::HTTP)
        expect(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(response)

        expect(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

        expect { local_cli.send(:maybe_create_github_release!, "1.2.3") }.not_to raise_error
      end
    end

    it "treats 422 already_exists as success" do
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
        allow(resp).to receive(:code).and_return("422")
        allow(resp).to receive(:body).and_return("{\"errors\":[{\"code\":\"already_exists\"}]}")

        http = instance_double(Net::HTTP)
        expect(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(resp)
        expect(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

        expect { local_cli.send(:maybe_create_github_release!, "2.0.0") }.not_to raise_error
      end
    end

    it "uses origin when preferred remote is nil" do
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
        allow(response).to receive(:code).and_return("500")
        allow(response).to receive(:body).and_return("oops")
        http = instance_double(Net::HTTP)
        expect(http).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(response)
        expect(Net::HTTP).to receive(:start).with("api.github.com", 443, use_ssl: true).and_yield(http)

        expect { local_cli.send(:maybe_create_github_release!, "3.0.0") }.not_to raise_error
      end
    end

    it "warns and skips when owner/repo cannot be determined" do
      stub_env("GITHUB_TOKEN" => "secret")
      cli = described_class.new
      allow(cli).to receive(:preferred_github_remote).and_return(nil)
      allow(cli).to receive(:remote_url).and_return("ssh://gitlab.com/user/repo")
      expect { cli.send(:maybe_create_github_release!, "1.0.0") }.not_to raise_error
    end
  end

  describe "release notes footer from FUNDING.md" do
    it "appends footer from FUNDING.md between tags with a leading blank line" do
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

    it "rewrites consecutive years into a range in both files" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "README.md"), "Copyright (c) 2023, 2024, 2025 Example")
        File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) 2023, 2024, 2025 Example")
        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        expect(File.read(File.join(root, "README.md"))).to include("2023-2025")
        expect(File.read(File.join(root, "LICENSE.txt"))).to include("2023-2025")
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

    it "injects current year into both files when missing and sets match" do
      Dir.mktmpdir do |root|
        current_year = Time.now.year
        last_year = current_year - 1
        File.write(File.join(root, "README.md"), "Copyright (c) #{last_year} Example")
        File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) #{last_year} Example")
        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        expect(File.read(File.join(root, "README.md"))).to include("#{last_year}-#{current_year}")
        expect(File.read(File.join(root, "LICENSE.txt"))).to include("#{last_year}-#{current_year}")
      end
    end
  end
end
