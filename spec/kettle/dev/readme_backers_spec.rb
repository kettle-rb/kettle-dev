# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/LeakyConstantDeclaration, ThreadSafety/ClassInstanceVariable, RSpec/InstanceVariable, RSpec/VerifiedDoubles

RSpec.describe Kettle::Dev::ReadmeBackers do
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
      # Required by ReadmeBackers#validate
      "README_UPDATER_TOKEN" => "test-token",
    )
  end

  describe "#run!" do
    context "when backers and sponsors content is unchanged" do
      it "prints no changes and returns without writing", :check_output do
        # Arrange members and README matching generated markdown
        backers_members = [
          Kettle::Dev::ReadmeBackers::Backer.new(name: "Alice", image: nil, website: "https://a.example", profile: nil),
        ]
        sponsors_members = [
          Kettle::Dev::ReadmeBackers::Backer.new(name: "", image: "", website: "", profile: ""),
        ]
        raw = [
          {"name" => "Alice", "image" => nil, "website" => "https://a.example", "profile" => nil, "role" => "BACKER", "tier" => "Backer"},
          {"name" => "", "image" => "", "website" => "", "profile" => "", "role" => "BACKER", "tier" => "Sponsor"},
        ]
        allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)
        backers_md = instance.send(:generate_markdown, backers_members, empty_message: "No backers yet. Be the first!", default_name: "Backer")
        sponsors_md = instance.send(:generate_markdown, sponsors_members, empty_message: "No sponsors yet. Be the first!", default_name: "Sponsor")
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
        allow(instance).to receive(:fetch_all_backers_raw).and_return([])
        allow(instance).to receive(:perform_git_commit)
        allow(File).to receive(:write)
        instance.run!
        expect(instance).not_to have_received(:perform_git_commit)
        expect(File).not_to have_received(:write)
      end
    end

    context "when both sections change" do
      it "writes file, prints update message, and commits when in git repo", :check_output do
        # Prepare README with tags but different content to force changes
        initial = [
          "# Title",
          tags[:generic_start],
          "old backers",
          tags[:generic_end],
          "",
          tags[:orgs_start],
          "old sponsors",
          tags[:orgs_end],
          "",
        ].join("\n")
        File.write(tmp_readme, initial)

        # Members that will generate different markdown
        raw = [
          {"name" => "Alice", "image" => nil, "website" => nil, "profile" => "https://github.com/Alice", "role" => "BACKER", "tier" => "Backer"},
          {"name" => "Acme", "image" => nil, "website" => "https://acme.example", "profile" => nil, "role" => "BACKER", "tier" => "Sponsor"},
        ]
        allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)

        # In a git repo, ensure commit is attempted
        allow(instance).to receive(:git_repo?).and_return(true)
        allow(instance).to receive(:perform_git_commit)

        expect {
          instance.run!
        }.to output(a_string_matching(/Updated backers and sponsors sections? in/)).to_stdout

        # File should have been updated
        content = File.read(tmp_readme)
        expect(content).to include(tags[:generic_start])
        expect(content).to include(tags[:orgs_start])
        expect(content).to include("[![Alice]")
        expect(content).to include("[![Acme]")

        expect(instance).to have_received(:perform_git_commit).with(kind_of(Array), kind_of(Array))
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

    it "reads handle from actual .opencollective.yml in repo root without stubbing" do
      stub_env("OPENCOLLECTIVE_HANDLE" => nil)
      path = described_class::OC_YML_PATH
      expect(File.file?(path)).to be true
      expect(described_class.new(readme_path: tmp_readme).send(:resolve_handle)).to eq("kettle-rb")
    end

    it "aborts when missing" do
      allow(File).to receive(:file?).with(described_class::OC_YML_PATH).and_return(false)
      expect { described_class.new(readme_path: tmp_readme).send(:resolve_handle) }.to raise_error(MockSystemExit)
    end
  end

  describe "#fetch_all_backers_raw" do
    let(:success) { instance_double(Net::HTTPSuccess, body: JSON.dump([{ "name" => "N", "image" => "", "website" => "", "profile" => "", "role" => "BACKER", "tier" => "Backer" }])) }

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

      instance.send(:fetch_all_backers_raw)

      expect(captured_req).to be_a(Net::HTTP::Get)
      expect(captured_req["User-Agent"]).to eq("kettle-dev/README-backers")
    end

    it "returns parsed raw hashes on success filtered by role BACKER" do
      allow(Net::HTTP).to receive(:start).and_return(success)
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      res = instance.send(:fetch_all_backers_raw)
      expect(res).to all(be_a(Hash))
      expect(res.first["tier"]).to eq("Backer")
    end

    it "returns [] when not success" do
      failure = instance_double(Net::HTTPResponse)
      allow(Net::HTTP).to receive(:start).and_return(failure)
      allow(failure).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      expect(instance.send(:fetch_all_backers_raw)).to eq([])
    end

    it "rescues JSON parsing error" do
      bad = instance_double(Net::HTTPSuccess, body: "not json")
      allow(Net::HTTP).to receive(:start).and_return(bad)
      allow(bad).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      expect(instance.send(:fetch_all_backers_raw)).to eq([])
    end

    it "rescues other StandardError" do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("boom"))
      expect(instance.send(:fetch_all_backers_raw)).to eq([])
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

    it "uses profile first, then website, then name" do
      m_profile = Kettle::Dev::ReadmeBackers::Backer.new(name: "John", image: nil, website: "https://Site", profile: "https://Profile")
      m_website = Kettle::Dev::ReadmeBackers::Backer.new(name: "John", image: nil, website: "https://Site", profile: " ")
      m_name = Kettle::Dev::ReadmeBackers::Backer.new(name: " John ", image: nil, website: nil, profile: nil)
      expect(instance.send(:identity_for_member, m_profile)).to eq("https://profile")
      expect(instance.send(:identity_for_member, m_website)).to eq("https://site")
      expect(instance.send(:identity_for_member, m_name)).to eq("john")
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

  describe "additional run! scenarios" do
    it "updates only backers section and uses singular 'section' message", :check_output do
      # README with both tags; backers will change, sponsors unchanged
      instance_tags = instance.send(:tag_strings)
      initial_backers = [
        Kettle::Dev::ReadmeBackers::Backer.new(name: "Old", image: nil, website: nil, profile: nil),
      ]
      initial_backers_md = instance.send(:generate_markdown, initial_backers, empty_message: "No backers yet. Be the first!", default_name: "Backer")
      initial_sponsors = [
        Kettle::Dev::ReadmeBackers::Backer.new(name: "Org", image: nil, website: "https://org.example", profile: nil),
      ]
      initial_sponsors_md = instance.send(:generate_markdown, initial_sponsors, empty_message: "No sponsors yet. Be the first!", default_name: "Sponsor")
      File.write(tmp_readme, [
        instance_tags[:generic_start],
        initial_backers_md,
        instance_tags[:generic_end],
        instance_tags[:orgs_start],
        initial_sponsors_md,
        instance_tags[:orgs_end],
      ].join("\n"))

      # New backers different; sponsors same so no change for sponsors
      raw = [
        {"name" => "Alice", "image" => nil, "website" => nil, "profile" => "https://github.com/alice", "role" => "BACKER", "tier" => "Backer"},
        {"name" => "Org", "image" => nil, "website" => "https://org.example", "profile" => nil, "role" => "BACKER", "tier" => "Sponsor"},
      ]
      allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)
      allow(instance).to receive(:git_repo?).and_return(true)
      allow(instance).to receive(:perform_git_commit)

      expect { instance.run! }.to output(a_string_matching(/Updated backers section in/)).to_stdout
      expect(File.read(tmp_readme)).to include("[![Alice]")
      expect(instance).to have_received(:perform_git_commit)
    end

    it "updates only sponsors section and uses singular 'section' message", :check_output do
      instance_tags = instance.send(:tag_strings)
      initial_backers = [Kettle::Dev::ReadmeBackers::Backer.new(name: "Old", image: nil, website: nil, profile: nil)]
      initial_backers_md = instance.send(:generate_markdown, initial_backers, empty_message: "No backers yet. Be the first!", default_name: "Backer")
      File.write(tmp_readme, [
        instance_tags[:generic_start],
        initial_backers_md,
        instance_tags[:generic_end],
        instance_tags[:orgs_start],
        "old sponsors",
        instance_tags[:orgs_end],
      ].join("\n"))

      raw = [
        {"name" => "Old", "image" => nil, "website" => nil, "profile" => nil, "role" => "BACKER", "tier" => "Backer"},
        {"name" => "Acme", "image" => nil, "website" => "https://acme.example", "profile" => nil, "role" => "BACKER", "tier" => "Sponsor"},
      ]
      allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)
      allow(instance).to receive(:git_repo?).and_return(true)
      allow(instance).to receive(:perform_git_commit)

      expect { instance.run! }.to output(a_string_matching(/Updated sponsors section in/)).to_stdout
      expect(File.read(tmp_readme)).to include("[![Acme]")
      expect(instance).to have_received(:perform_git_commit)
    end

    it "does not commit when not in a git repo even if content changes", :check_output do
      instance_tags = instance.send(:tag_strings)
      File.write(tmp_readme, [
        instance_tags[:generic_start],
        "old",
        instance_tags[:generic_end],
      ].join("\n"))
      raw = [
        {"name" => "A", "image" => nil, "website" => nil, "profile" => nil, "role" => "BACKER", "tier" => "Backer"},
      ]
      allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)
      allow(instance).to receive(:git_repo?).and_return(false)
      expect(instance).not_to receive(:perform_git_commit)
      instance.run!
    end

    it "handles when only one tag pair exists (backers) and sponsors tag missing", :check_output do
      instance_tags = instance.send(:tag_strings)
      File.write(tmp_readme, [
        instance_tags[:generic_start],
        "old",
        instance_tags[:generic_end],
      ].join("\n"))
      raw = [
        {"name" => "A", "image" => nil, "website" => nil, "profile" => nil, "role" => "BACKER", "tier" => "Backer"},
      ]
      allow(instance).to receive(:fetch_all_backers_raw).and_return(raw)
      allow(instance).to receive(:git_repo?).and_return(true)
      allow(instance).to receive(:perform_git_commit)
      expect { instance.run! }.to output(a_string_matching(/Updated backers section in/)).to_stdout
      expect(instance).to have_received(:perform_git_commit)
    end
  end

  describe "edge cases for helpers" do
    it "replace_between_tags returns :not_found when end before start" do
      start_tag = "<!-- S:START -->"
      end_tag = "<!-- S:END -->"
      # Force indices such that end appears before start
      content = "#{end_tag} middle #{start_tag}"
      expect(instance.send(:replace_between_tags, content, start_tag, end_tag, "X")).to eq(:not_found)
    end

    it "extract_section_identities returns empty set when tags not found" do
      ids = instance.send(:extract_section_identities, "content", :not_found, :not_found)
      expect(ids).to be_a(Set)
      expect(ids).to be_empty
    end

    it "readme_osc_tag rescues YAML errors and falls back to default" do
      yml_path = described_class::OC_YML_PATH
      allow(File).to receive(:file?).with(yml_path).and_return(true)
      allow(File).to receive(:read).with(yml_path).and_raise(StandardError.new("fail"))
      expect(instance.send(:readme_osc_tag)).to eq(described_class::README_OSC_TAG_DEFAULT)
    end

    it "commit_subject rescues YAML errors and falls back to default" do
      yml_path = described_class::OC_YML_PATH
      allow(File).to receive(:file?).with(yml_path).and_return(true)
      allow(File).to receive(:read).with(yml_path).and_raise(StandardError.new("fail"))
      expect(instance.send(:commit_subject)).to eq(described_class::COMMIT_SUBJECT_DEFAULT)
    end

    it "generate_markdown prefers website over profile and uses default avatar" do
      m = Kettle::Dev::ReadmeBackers::Backer.new(name: "Name", image: nil, website: "https://web", profile: "https://profile")
      md = instance.send(:generate_markdown, [m], empty_message: "none", default_name: "X")
      expect(md).to include("(https://web)")
      expect(md).to include(Kettle::Dev::ReadmeBackers::DEFAULT_AVATAR)
    end
  end

  describe "perform_git_commit message composition" do
    it "includes only Backers line when only backers are present" do
      allow(instance).to receive(:commit_subject).and_return("Title")
      allow(instance).to receive(:system).with("git", "add", tmp_readme).and_return(true)
      allow(instance).to receive(:system).with("git", "diff", "--cached", "--quiet").and_return(false)
      allow(instance).to receive(:system).with("git", "commit", "-m", a_string_including("Backers:")).and_return(true)
      allow(instance).to receive(:system).with("git", "commit", "-m", a_string_including("Subscribers:")).and_return(true)
      backer = Kettle::Dev::ReadmeBackers::Backer.new(name: "X", image: nil, website: "https://github.com/x", profile: nil)
      instance.send(:perform_git_commit, [backer], [])
      expect(instance).to have_received(:system).with("git", "commit", "-m", a_string_including("Backers:"))
      expect(instance).not_to have_received(:system).with("git", "commit", "-m", a_string_including("Subscribers:"))
    end

    it "includes only Subscribers line when only sponsors are present" do
      allow(instance).to receive(:commit_subject).and_return("Title")
      allow(instance).to receive(:system).with("git", "add", tmp_readme).and_return(true)
      allow(instance).to receive(:system).with("git", "diff", "--cached", "--quiet").and_return(false)
      allow(instance).to receive(:system).with("git", "commit", "-m", a_string_including("Subscribers:")).and_return(true)
      allow(instance).to receive(:system).with("git", "commit", "-m", a_string_including("Backers:")).and_return(true)
      sponsor = Kettle::Dev::ReadmeBackers::Backer.new(name: "S", image: nil, website: "https://github.com/s", profile: nil)
      instance.send(:perform_git_commit, [], [sponsor])
      expect(instance).to have_received(:system).with("git", "commit", "-m", a_string_including("Subscribers:"))
      expect(instance).not_to have_received(:system).with("git", "commit", "-m", a_string_including("Backers:"))
    end
  end

  describe "#validate" do
    it "raises with guidance to org secrets when token missing and REPO set" do
      stub_env(
        "README_UPDATER_TOKEN" => nil,
        "REPO" => "acme/widgets",
        "GITHUB_REPOSITORY" => nil,
      )
      expect {
        expect {
          instance.validate
        }.to raise_error(RuntimeError, 'Missing ENV["README_UPDATER_TOKEN"]')
      }.to output(
        a_string_including(
          "ERROR: README_UPDATER_TOKEN is not set.\n",
        ).and(
          a_string_including("Please create an organization-level Actions secret named README_UPDATER_TOKEN at:"),
        ).and(
          a_string_including("https://github.com/organizations/acme/settings/secrets/actions"),
        ).and(
          a_string_including("Then update the workflow to reference it, or provide README_UPDATER_TOKEN in the environment."),
        ),
      ).to_stderr
    end

    it "returns nil and does not print when token is present" do
      stub_env(
        "README_UPDATER_TOKEN" => "abc123",
        "REPO" => nil,
        "GITHUB_REPOSITORY" => nil,
      )
      expect { expect(instance.validate).to be_nil }.not_to output.to_stderr
    end
  end
end

# rubocop:enable RSpec/MultipleExpectations, RSpec/MessageSpies, RSpec/LeakyConstantDeclaration, ThreadSafety/ClassInstanceVariable, RSpec/InstanceVariable, RSpec/VerifiedDoubles
