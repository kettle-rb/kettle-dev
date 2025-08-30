# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  let(:ci_helpers) { Kettle::Dev::CIHelpers }

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
