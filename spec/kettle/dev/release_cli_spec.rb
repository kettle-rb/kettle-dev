# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/StubbedMock, RSpec/ReceiveMessages

RSpec.describe Kettle::Dev::ReleaseCLI do
  include_context "with stubbed env"

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
      expect { cli.send(:ensure_bundler_2_7_plus!) }.to raise_error(SystemExit, /Bundler is required/)
    end

    it "aborts when bundler version is too low" do
      stub_const("Bundler", Class.new)
      stub_const("Bundler::VERSION", "2.6.9")
      expect { cli.send(:ensure_bundler_2_7_plus!) }.to raise_error(SystemExit, /requires Bundler >= 2.7.0/)
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

  describe "#commit_release_prep!" do
    it "returns false when no changes" do
      allow(cli).to receive(:git_output).with(["status", "--porcelain"]).and_return(["", true])
      expect(cli.send(:commit_release_prep!, "1.0.0")).to be false
    end

    it "commits and returns true when there are changes" do
      allow(cli).to receive(:git_output).with(["status", "--porcelain"]).and_return([" M file", true])
      expect(cli).to receive(:run_cmd!).with(/git commit -am/)
      expect(cli.send(:commit_release_prep!, "1.0.0")).to be true
    end
  end

  describe "#push!" do
    it "aborts when branch is unknown" do
      allow(cli).to receive(:current_branch).and_return(nil)
      expect { cli.send(:push!) }.to raise_error(SystemExit, /Could not determine current branch/)
    end

    it "pushes to 'all' and force-pushes on failure" do
      allow(cli).to receive(:current_branch).and_return("feat")
      allow(cli).to receive(:has_remote?).with("all").and_return(true)
      expect(cli).to receive(:system).with("git push all feat").and_return(false)
      expect(cli).to receive(:run_cmd!).with("git push -f all feat")
      cli.send(:push!)
    end

    it "pushes branch with no remotes and force on failure" do
      allow(cli).to receive(:current_branch).and_return("feat")
      allow(cli).to receive(:has_remote?).with("all").and_return(false)
      allow(cli).to receive(:has_remote?).with("origin").and_return(false)
      allow(cli).to receive(:github_remote_candidates).and_return([])
      allow(cli).to receive(:gitlab_remote_candidates).and_return([])
      allow(cli).to receive(:codeberg_remote_candidates).and_return([])
      expect(cli).to receive(:system).with("git push feat").and_return(false)
      expect(cli).to receive(:run_cmd!).with("git push -f feat")
      cli.send(:push!)
    end

    it "pushes to multiple remotes and force on failures" do
      allow(cli).to receive(:current_branch).and_return("feat")
      allow(cli).to receive(:has_remote?).with("all").and_return(false)
      allow(cli).to receive(:has_remote?).with("origin").and_return(true)
      allow(cli).to receive(:github_remote_candidates).and_return(["github"])
      allow(cli).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
      allow(cli).to receive(:codeberg_remote_candidates).and_return([])
      expect(cli).to receive(:system).with("git push origin feat").and_return(true)
      expect(cli).to receive(:system).with("git push github feat").and_return(false)
      expect(cli).to receive(:run_cmd!).with("git push -f github feat")
      expect(cli).to receive(:system).with("git push gitlab feat").and_return(true)
      cli.send(:push!)
    end
  end

  describe "git helpers" do
    it "detects trunk branch from origin remote output" do
      out = "Remote HEAD branch: main\n  HEAD branch: main\n"
      allow(cli).to receive(:git_output).with(["remote", "show", "origin"]).and_return([out, true])
      expect(cli.send(:detect_trunk_branch)).to eq("main")
    end

    it "parses remotes_with_urls and candidates" do
      remote_v = <<~TXT
        origin\tgit@github.com:me/repo.git (fetch)
        origin\tgit@github.com:me/repo.git (push)
        github\thttps://github.com/me/repo.git (fetch)
        gl\thttps://gitlab.com/me/repo (fetch)
        cb\tgit@codeberg.org:me/repo.git (fetch)
      TXT
      allow(cli).to receive(:git_output).with(["remote", "-v"]).and_return([remote_v, true])
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
      expect { cli.send(:ensure_trunk_synced_before_push!, "main", "feat") }.to raise_error(SystemExit, /missing commits present on: origin/)
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
    it "returns early when SKIP_GEM_SIGNING is set" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli.send(:ensure_signing_setup_or_skip!)).to be_nil
    end

    it "aborts when cert is missing and signing enabled" do
      Dir.mktmpdir do |root|
        allow(ci_helpers).to receive(:project_root).and_return(root)
        other = described_class.new
        stub_env("SKIP_GEM_SIGNING" => nil, "GEM_CERT_USER" => "alice", "USER" => "bob")
        expect { other.send(:ensure_signing_setup_or_skip!) }.to raise_error(SystemExit, /no public cert/)
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
        expect { local_cli.send(:validate_checksums!, "1.0.0", stage: "stage") }.to raise_error(SystemExit, /SHA256 mismatch/)
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
      allow(cli).to receive(:preferred_github_remote).and_return("origin")
      allow(cli).to receive(:remote_url).with("origin").and_return("git@github.com:me/repo.git")
    end

    it "aborts when branch cannot be determined" do
      allow(ci_helpers).to receive(:current_branch).and_return(nil)
      expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(SystemExit, /Could not determine current branch/)
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
      run = {"html_url" => "http://example/ci"}
      allow(ci_helpers).to receive(:latest_run).and_return(run)
      allow(ci_helpers).to receive(:success?).and_return(false)
      allow(ci_helpers).to receive(:failed?).and_return(true)
      expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(SystemExit, /Workflow failed/)
    end

    it "handles GitLab pipeline success" do
      allow(cli).to receive(:preferred_github_remote).and_return(nil)
      allow(ci_helpers).to receive(:workflows_list).and_return([])
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(ci_helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])
      pipe = {"web_url" => "http://gitlab/pipeline"}
      allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
      allow(ci_helpers).to receive(:gitlab_success?).and_return(true)
      allow(ci_helpers).to receive(:gitlab_failed?).and_return(false)
      allow(cli).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
      expect { cli.send(:monitor_workflows_after_push!) }.not_to raise_error
    end

    it "aborts when GitLab pipeline fails" do
      allow(cli).to receive(:preferred_github_remote).and_return(nil)
      allow(ci_helpers).to receive(:workflows_list).and_return([])
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(ci_helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])
      pipe = {"web_url" => "http://gitlab/pipeline"}
      allow(ci_helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
      allow(ci_helpers).to receive(:gitlab_success?).and_return(false)
      allow(ci_helpers).to receive(:gitlab_failed?).and_return(true)
      allow(cli).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
      expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(SystemExit, /Pipeline failed/)
    end

    it "aborts when no CI configured" do
      allow(ci_helpers).to receive(:workflows_list).and_return([])
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      allow(cli).to receive(:preferred_github_remote).and_return(nil)
      allow(cli).to receive(:gitlab_remote_candidates).and_return([])
      expect { cli.send(:monitor_workflows_after_push!) }.to raise_error(SystemExit, /CI configuration not detected/)
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/StubbedMock, RSpec/ReceiveMessages
