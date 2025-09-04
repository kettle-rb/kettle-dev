# frozen_string_literal: true

RSpec.describe Kettle::Dev::PreReleaseCLI do
  describe Kettle::Dev::PreReleaseCLI::Markdown do
    it "extracts inline, reference, and html image urls" do
      md = <<~MD
        ![alt](https://example.com/a.png)
        ![alt][ref]
        [ref]: https://example.com/b.jpg
        <img src="https://example.com/c.gif" />
        <img src='https://example.com/d.webp'>
        ![alt](./local.png)
      MD
      urls = described_class.extract_image_urls_from_text(md)
      expect(urls).to contain_exactly(
        "https://example.com/a.png",
        "https://example.com/b.jpg",
        "https://example.com/c.gif",
        "https://example.com/d.webp",
      )
    end

    it "extracts from files matching glob and de-duplicates" do
      Dir.mktmpdir do |root|
        f1 = File.join(root, "a.md")
        f2 = File.join(root, "b.md")
        File.write(f1, "![x](https://e.com/a.png)\n")
        File.write(f2, "![x](https://e.com/a.png) ![y](https://e.com/b.png)\n")
        # Avoid Dir.chdir for thread safety; pass absolute glob
        urls = described_class.extract_image_urls_from_files(File.join(root, "*.md"))
        expect(urls.sort).to eq(["https://e.com/a.png", "https://e.com/b.png"])
      end
    end
  end

  describe Kettle::Dev::PreReleaseCLI::HTTP do
    it "returns false on unsupported scheme" do
      expect {
        described_class.head_ok?("ftp://example.com/a")
      }.to raise_error(ArgumentError)
    end

    # rubocop:disable RSpec/VerifiedDoubles
    it "falls back to GET when method not allowed and returns true on success" do
      method_not_allowed = double("MethodNotAllowed")
      allow(method_not_allowed).to receive(:is_a?).with(Net::HTTPMethodNotAllowed).and_return(true)

      success = double("Success")
      allow(success).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      http = double("HTTP")
      # Simulate Net::HTTP.start yielding http and returning the block value
      allow(http).to receive(:start).and_yield(http)
      # First request returns method not allowed; second (GET) returns success
      allow(http).to receive(:request).and_return(method_not_allowed, success)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:ssl_timeout=)
      allow(http).to receive(:verify_mode=)
      allow(http).to receive(:use_ssl?).and_return(true)

      allow(Net::HTTP).to receive(:new).and_return(http)

      expect(described_class.head_ok?("https://example.org/x")).to be(true)
    end
    # rubocop:enable RSpec/VerifiedDoubles
  end

  describe "CLI run flow" do
    it "runs check 1 and completes without abort when all links pass", :check_output do
      cli = described_class.new(check_num: 1)
      allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([
        "https://e.com/a.png", "https://e.com/b.png",
      ])
      allow(Kettle::Dev::PreReleaseCLI::HTTP).to receive(:head_ok?).and_return(true)
      expect { cli.run }.not_to raise_error
    end

    it "aborts via ExitAdapter when failures occur" do
      cli = described_class.new(check_num: 1)
      allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([
        "https://e.com/a.png", "https://e.com/b.png",
      ])
      allow(Kettle::Dev::PreReleaseCLI::HTTP).to receive(:head_ok?).and_return(true, false)
      expect { cli.run }.to raise_error(MockSystemExit)
    end

    it "respects starting check index (no-op when > number of checks)" do
      cli = described_class.new(check_num: 2)
      expect { cli.run }.not_to raise_error
    end
  end
end
