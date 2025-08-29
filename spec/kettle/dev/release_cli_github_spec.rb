# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  let(:ci_helpers) { Kettle::Dev::CIHelpers }
  let(:cli) { described_class.new }

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
      expect { cli.send(:maybe_create_github_release!, "1.2.3") }.not_to raise_error
    end

    it "creates a release with title and body from CHANGELOG when token present" do
      Dir.mktmpdir do |root|
        # Prepare a minimal CHANGELOG with a section and links
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
      allow(cli).to receive(:preferred_github_remote).and_return(nil)
      allow(cli).to receive(:remote_url).and_return("ssh://gitlab.com/user/repo")
      expect { cli.send(:maybe_create_github_release!, "1.0.0") }.not_to raise_error
    end
  end
end
