# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/LeakyConstantDeclaration, ThreadSafety/ClassInstanceVariable, RSpec/InstanceVariable, RSpec/VerifiedDoubles

RSpec.describe Kettle::Dev::ReadmeBackers do
  include_context "with stubbed env"

  let(:tmp_readme) { File.join(Dir.mktmpdir, "README.md") }
  let(:instance) { described_class.new(handle: "test-oc", readme_path: tmp_readme) }
  let(:default_base) { "OPENCOLLECTIVE" }
  let(:tags) do
    {
      generic_start: "<!-- #{default_base}:START -->",
      generic_end: "<!-- #{default_base}:END -->",
      individuals_start: "<!-- #{default_base}-INDIVIDUALS:START -->",
      individuals_end: "<!-- #{default_base}-INDIVIDUALS:END -->",
      orgs_start: "<!-- #{default_base}-ORGANIZATIONS:START -->",
      orgs_end: "<!-- #{default_base}-ORGANIZATIONS:END -->",
    }
  end

  before do
    # Ensure default env unless specific test overrides
    stub_env(
      "KETTLE_DEV_BACKER_README_OSC_TAG" => nil,
      "OPENCOLLECTIVE_HANDLE" => nil,
      "KETTLE_README_BACKERS_COMMIT_SUBJECT" => nil,
    )
  end

  describe "#run!" do
    context "when backers and sponsors content is unchanged" do
      it "prints no changes and returns without writing", :check_output do
        # Arrange members and README matching generated markdown
        members = [
          Kettle::Dev::ReadmeBackers::Backer.new(name: "Alice", image: nil, website: "https://a.example", profile: nil),
          Kettle::Dev::ReadmeBackers::Backer.new(name: "", image: "", website: "", profile: ""),
        ]
        allow(instance).to receive(:fetch_members).with("backers.json").and_return(members)
        allow(instance).to receive(:fetch_members).with("sponsors.json").and_return(members)
        backers_md = instance.send(:generate_markdown, members, empty_message: "No backers yet. Be the first!", default_name: "Backer")
        sponsors_md = instance.send(:generate_markdown, members, empty_message: "No sponsors yet. Be the first!", default_name: "Sponsor")
        content = [
          "# Title",
          tags[:generic_start],
          backers_md,
          tags[:generic_end],
          "",
          tags[:orgs_start],
          sponsors_md,
          tags[:orgs_end],
          "",
        ].join("\n")
        File.write(tmp_readme, content)

        expect(File).not_to receive(:write)

        instance.run!
      end
    end

    context "when no recognized tags are present" do
      it "warns and returns", :check_output do
        File.write(tmp_readme, "# No tags here\n")
        allow(instance).to receive(:fetch_members).and_return([])
        allow(instance).to receive(:perform_git_commit)
        allow(File).to receive(:write)
        instance.run!
        expect(instance).not_to have_received(:perform_git_commit)
        expect(File).not_to have_received(:write)
      end
    end
  end

  describe "#readme_osc_tag" do
    it "prefers ENV" do
      stub_env("KETTLE_DEV_BACKER_README_OSC_TAG" => "ENV_TAG")
      expect(instance.send(:readme_osc_tag)).to eq("ENV_TAG")
    end

    it "falls back to .opencollective.yml" do
      yml_path = described_class::OC_YML_PATH
      allow(File).to receive(:file?).with(yml_path).and_return(true)
      allow(File).to receive(:read).with(yml_path).and_return({"readme-osc-tag" => "YML_TAG"}.to_yaml)
      expect(instance.send(:readme_osc_tag)).to eq("YML_TAG")
    end

    it "defaults when none provided" do
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with(described_class::OC_YML_PATH).and_return(false)
      expect(instance.send(:readme_osc_tag)).to eq(described_class::README_OSC_TAG_DEFAULT)
    end
  end

  describe "#tag_strings" do
    it "builds tags from base" do
      expect(instance.send(:tag_strings)).to include(
        generic_start: tags[:generic_start],
        orgs_end: tags[:orgs_end],
      )
    end
  end

  describe "#resolve_handle" do
    it "returns env when present" do
      stub_env("OPENCOLLECTIVE_HANDLE" => "env_handle")
      expect(described_class.new(readme_path: tmp_readme).send(:resolve_handle)).to eq("env_handle")
    end

    it "reads from .opencollective.yml when no env" do
      yml_path = described_class::OC_YML_PATH
      allow(File).to receive(:file?).with(yml_path).and_return(true)
      allow(File).to receive(:read).with(yml_path).and_return({"collective" => "yml_handle"}.to_yaml)
      expect(described_class.new(readme_path: tmp_readme).send(:resolve_handle)).to eq("yml_handle")
    end

    it "aborts when missing" do
      allow(File).to receive(:file?).with(described_class::OC_YML_PATH).and_return(false)
      expect { described_class.new(readme_path: tmp_readme).send(:resolve_handle) }.to raise_error(SystemExit)
    end
  end

  describe "#fetch_members" do
    let(:success) { instance_double(Net::HTTPSuccess, body: JSON.dump([{"name" => "N", "image" => "", "website" => "", "profile" => ""}])) }

    it "sets headers and timeouts when fetching" do
      fake_response = instance_double(Net::HTTPSuccess, body: JSON.dump([]))
      allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      captured_req = nil
      conn = double("conn")
      expect(conn).to receive(:read_timeout=).with(10)
      expect(conn).to receive(:open_timeout=).with(5)
      allow(conn).to receive(:request) { |req|
        captured_req = req
        fake_response
      }
      allow(Net::HTTP).to receive(:start).and_yield(conn).and_return(fake_response)

      instance.send(:fetch_members, "backers.json")

      expect(captured_req).to be_a(Net::HTTP::Get)
      expect(captured_req["User-Agent"]).to eq("kettle-dev/README-backers")
    end

    it "returns parsed members on success" do
      allow(Net::HTTP).to receive(:start).and_return(success)
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      res = instance.send(:fetch_members, "backers.json")
      expect(res).to all(be_a(Kettle::Dev::ReadmeBackers::Backer))
      expect(res.first.image).to be_nil
      expect(res.first.website).to be_nil
      expect(res.first.profile).to be_nil
    end

    it "returns [] when not success" do
      failure = instance_double(Net::HTTPResponse)
      allow(Net::HTTP).to receive(:start).and_return(failure)
      allow(failure).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      expect(instance.send(:fetch_members, "backers.json")).to eq([])
    end

    it "rescues JSON parsing error" do
      bad = instance_double(Net::HTTPSuccess, body: "not json")
      allow(Net::HTTP).to receive(:start).and_return(bad)
      allow(bad).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      expect(instance.send(:fetch_members, "backers.json")).to eq([])
    end

    it "rescues other StandardError" do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("boom"))
      expect(instance.send(:fetch_members, "backers.json")).to eq([])
    end
  end

  describe "#generate_markdown" do
    it "returns empty message for none" do
      expect(instance.send(:generate_markdown, [], empty_message: "none", default_name: "X")).to eq("none")
    end

    it "builds image links with defaults and escapes" do
      m1 = Kettle::Dev::ReadmeBackers::Backer.new(name: "A[B]C", image: nil, website: nil, profile: "https://oc")
      md = instance.send(:generate_markdown, [m1], empty_message: "none", default_name: "X")
      expect(md).to include('A\\[B\\]C')
    end
  end

  describe "#replace_between_tags" do
    it "returns :not_found when tags missing" do
      expect(instance.send(:replace_between_tags, "abc", :not_found, "END", "x")).to eq(:not_found)
    end

    it "returns :no_change when unchanged" do
      content = "#{tags[:generic_start]}\nX\n#{tags[:generic_end]}"
      expect(instance.send(:replace_between_tags, content, tags[:generic_start], tags[:generic_end], "X")).to eq(:no_change)
    end

    it "replaces when changed" do
      content = "#{tags[:generic_start]}\nY\n#{tags[:generic_end]}"
      out = instance.send(:replace_between_tags, content, tags[:generic_start], tags[:generic_end], "Z")
      expect(out).to include("\nZ\n#{tags[:generic_end]}")
    end
  end

  describe "tag detection" do
    it "detects backer generic tags" do
      content = "#{tags[:generic_start]}\n#{tags[:generic_end]}"
      expect(instance.send(:detect_backer_tags, content)).to eq([tags[:generic_start], tags[:generic_end]])
    end

    it "detects backer individuals tags" do
      content = "#{tags[:individuals_start]}\n#{tags[:individuals_end]}"
      expect(instance.send(:detect_backer_tags, content)).to eq([tags[:individuals_start], tags[:individuals_end]])
    end

    it "detects sponsor tags present/absent" do
      content = "#{tags[:orgs_start]}\n#{tags[:orgs_end]}"
      expect(instance.send(:detect_sponsor_tags, content)).to eq([tags[:orgs_start], tags[:orgs_end]])
      expect(instance.send(:detect_sponsor_tags, "none")).to eq([:not_found, :not_found])
    end
  end

  describe "#extract_section_identities" do
    it "extracts href and alt identities, downcased" do
      block = [
        tags[:generic_start],
        "[![Alt Name](img)](https://Example.com)",
        "[![AnotherAlt](img)](https://site)",
        tags[:generic_end],
      ].join("\n")
      ids = instance.send(:extract_section_identities, block, tags[:generic_start], tags[:generic_end])
      expect(ids).to include("https://example.com")
      expect(ids).to include("anotheralt")
    end
  end

  describe "#compute_new_members and #identity_for_member" do
    it "computes new members based on identity precedence" do
      prev = Set.new(["https://x", "john doe"])
      m1 = Kettle::Dev::ReadmeBackers::Backer.new(name: "John Doe", image: nil, website: nil, profile: nil)
      m2 = Kettle::Dev::ReadmeBackers::Backer.new(name: "Jane", image: nil, website: "https://x", profile: nil)
      m3 = Kettle::Dev::ReadmeBackers::Backer.new(name: "", image: nil, website: "", profile: "")
      res = instance.send(:compute_new_members, prev, [m1, m2, m3])
      expect(res).to contain_exactly(m3)
      expect(instance.send(:identity_for_member, m3)).to eq("")
    end
  end

  describe "#mention_for_member" do
    it "uses github handle when present" do
      m = Kettle::Dev::ReadmeBackers::Backer.new(name: "X", image: nil, website: "https://github.com/foo", profile: nil)
      expect(instance.send(:mention_for_member, m)).to eq("@foo")
    end

    it "falls back to name or default" do
      m1 = Kettle::Dev::ReadmeBackers::Backer.new(name: "Zara", image: nil, website: nil, profile: nil)
      expect(instance.send(:mention_for_member, m1)).to eq("Zara")
      m2 = Kettle::Dev::ReadmeBackers::Backer.new(name: "  ", image: nil, website: nil, profile: nil)
      expect(instance.send(:mention_for_member, m2, default_name: "Member")).to eq("Member")
    end
  end

  describe "#github_handle_from_urls" do
    it "parses various github URL forms and ignores invalid" do
      urls = [
        "https://github.com/foo",
        "https://github.com/foo/",
        "https://github.com/Foo/bar",
        "https://github.com/sponsors/baz",
        "http://github.com/sponsors/baz/",
        "https://notgithub.com/x",
        "http://github.com/",
        "%%%baduri%%%",
      ]
      h1 = instance.send(:github_handle_from_urls, urls[0])
      h2 = instance.send(:github_handle_from_urls, urls[1])
      h3 = instance.send(:github_handle_from_urls, urls[2])
      h4 = instance.send(:github_handle_from_urls, urls[3])
      h5 = instance.send(:github_handle_from_urls, urls[4])
      h6 = instance.send(:github_handle_from_urls, urls[5])
      h7 = instance.send(:github_handle_from_urls, urls[6])
      h8 = instance.send(:github_handle_from_urls, urls[7])
      expect(h1).to eq("foo")
      expect(h2).to eq("foo")
      expect(h3).to eq("Foo") # case preserved then sanitized later if needed
      expect(h4).to eq("baz")
      expect(h5).to eq("baz")
      expect(h6).to eq("x")
      expect(h7).to be_nil
      expect(h8).to be_nil
    end

    it "sanitizes non-alnum and dashes" do
      expect(instance.send(:github_handle_from_urls, "https://github.com/f$o$o!")).to eq("foo")
    end
  end

  describe "#perform_git_commit" do
    it "returns early when no staged changes" do
      allow(instance).to receive(:mention_for_member).and_call_original
      allow(instance).to receive(:commit_subject).and_return("Title")
      # Simulate system calls: add, then diff --cached --quiet returns true (no changes)
      allow(instance).to receive(:system).with("git", "add", tmp_readme).and_return(true)
      allow(instance).to receive(:system).with("git", "diff", "--cached", "--quiet").and_return(true)
      expect(instance).not_to receive(:system).with("git", "commit", any_args)
      instance.send(:perform_git_commit, [], [])
    end

    it "commits when there are staged changes" do
      allow(instance).to receive(:commit_subject).and_return("Title")
      allow(instance).to receive(:system).with("git", "add", tmp_readme).and_return(true)
      allow(instance).to receive(:system).with("git", "diff", "--cached", "--quiet").and_return(false)
      expect(instance).to receive(:system).with("git", "commit", "-m", a_string_including("Title"))
      instance.send(:perform_git_commit, [Kettle::Dev::ReadmeBackers::Backer.new(name: "X", image: nil, website: "https://github.com/y", profile: nil)], [])
    end
  end

  describe "#commit_subject" do
    it "prefers ENV over others" do
      stub_env("KETTLE_README_BACKERS_COMMIT_SUBJECT" => "ENV_SUBJ")
      expect(instance.send(:commit_subject)).to eq("ENV_SUBJ")
    end

    it "falls back to yml" do
      yml_path = described_class::OC_YML_PATH
      allow(File).to receive(:file?).with(yml_path).and_return(true)
      allow(File).to receive(:read).with(yml_path).and_return({"readme-backers-commit-subject" => "YML_SUBJ"}.to_yaml)
      expect(instance.send(:commit_subject)).to eq("YML_SUBJ")
    end

    it "uses default when none provided" do
      allow(File).to receive(:file?).with(described_class::OC_YML_PATH).and_return(false)
      expect(instance.send(:commit_subject)).to eq(described_class::COMMIT_SUBJECT_DEFAULT)
    end
  end

  describe "#git_repo?" do
    it "delegates to system" do
      allow(instance).to receive(:system).with("git", "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL).and_return(true)
      expect(instance.send(:git_repo?)).to be true
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/LeakyConstantDeclaration, ThreadSafety/ClassInstanceVariable, RSpec/InstanceVariable, RSpec/VerifiedDoubles
