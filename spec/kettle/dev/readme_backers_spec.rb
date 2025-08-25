# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReadmeBackers do
  include_context "with stubbed env"

  let(:handle) { "some-collective" }

  def make_readme_with_tags(path)
    File.write(path, <<~MD)
      # Project

      <!-- OPENCOLLECTIVE:START -->
      Old backers content
      <!-- OPENCOLLECTIVE:END -->

      <!-- OPENCOLLECTIVE-ORGANIZATIONS:START -->
      Old sponsors content
      <!-- OPENCOLLECTIVE-ORGANIZATIONS:END -->
    MD
  end

  it "updates both backers and sponsors sections using fetch_members results" do
    Dir.mktmpdir do |dir|
      readme_path = File.join(dir, "README.md")
      make_readme_with_tags(readme_path)

      stub_env("OPENCOLLECTIVE_HANDLE" => handle)

      rb = described_class.new(readme_path: readme_path)

      # Avoid any git operations
      allow(rb).to receive(:git_repo?).and_return(false)
      # Stub network calls
      b1 = Kettle::Dev::ReadmeBackers::Backer.new(name: "Alice", image: "https://img/a.png", website: "https://example.com/alice")
      s1 = Kettle::Dev::ReadmeBackers::Backer.new(name: "Org", image: "https://img/o.png", profile: "https://github.com/orgs/acme")
      allow(rb).to receive(:fetch_members).with("backers.json").and_return([b1])
      allow(rb).to receive(:fetch_members).with("sponsors.json").and_return([s1])

      expect { rb.run! }.not_to raise_error

      content = File.read(readme_path)
      expect(content).to include("[![Alice](https://img/a.png)](https://example.com/alice)")
      expect(content).to include("[![Org](https://img/o.png)](https://github.com/orgs/acme)")
    end
  end

  it "prints informative message when tags are missing and nothing to update" do
    Dir.mktmpdir do |dir|
      readme_path = File.join(dir, "README.md")
      File.write(readme_path, "# No tags here\n")
      stub_env("OPENCOLLECTIVE_HANDLE" => handle)

      rb = described_class.new(readme_path: readme_path)
      allow(rb).to receive(:git_repo?).and_return(false)
      allow(rb).to receive(:fetch_members).and_return([])

      # No exception expected; command prints a message and returns
      expect { rb.run! }.not_to raise_error
      expect(File.read(readme_path)).to include("# No tags here")
    end
  end
end
