# frozen_string_literal: true

RSpec.describe Kettle::Dev::PreReleaseCLI do
  it "normalizes unicode URLs in markdown files (check 1)" do
    Dir.mktmpdir do |root|
      file = File.join(root, "README.md")
      url = "https://img.shields.io/badge/buy_me_a_coffee-\u2713-a51611.svg?style=flat"
      md = "![coffee](#{url})\n"
      File.write(file, md)

      # rubocop:disable ThreadSafety/DirChdir
      Dir.chdir(root) do
        cli = described_class.new(check_num: 1)
        # Avoid running actual HTTP in check 2 for this example; focus on check 1 behavior
        allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([])
        # Wrap in VCR so any incidental HTTP is blocked deterministically
        VCR.use_cassette("head_image_ok") do
          expect { cli.run }.not_to raise_error
        end
        content = File.read(file)
        # After normalization, the URL should not be exactly equal to the raw unicode url string
        # (Addressable will percent-encode the checkmark in path)
        expect(content).not_to include(url)
        # And it should still be a shields URL
        expect(content).to include("https://img.shields.io/badge/")
      end
      # rubocop:enable ThreadSafety/DirChdir
    end
  end

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

    it "performs a HEAD request for an image URL using VCR and replays it across specs", :vcr do
      # Use a stable endpoint that supports HEAD with 200 response
      url = "https://httpbin.org/image/png"
      VCR.use_cassette("head_image_ok") do
        expect(described_class.head_ok?(url)).to be(true)
      end
    end
  end

  describe "CLI run flow" do
    it "runs checks 1 and 2 and completes without abort when all links pass", :check_output do
      cli = described_class.new(check_num: 1)
      # Provide a deterministic URL and use VCR to avoid network
      allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([
        "https://httpbin.org/image/png",
      ])
      expect {
        VCR.use_cassette("head_image_ok") { cli.run }
      }.not_to raise_error
    end

    it "aborts via ExitAdapter when HTTP failures occur in check 2" do
      cli = described_class.new(check_num: 2)
      allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([
        "https://httpbin.org/image/png", "https://example.invalid/missing.png",
      ])
      # First will be OK via cassette; second will fail (no cassette and blocked net), so stub head_ok? only for failure path
      allow(Kettle::Dev::PreReleaseCLI::HTTP).to receive(:head_ok?).and_wrap_original do |m, url|
        if url.include?("httpbin.org")
          VCR.use_cassette("head_image_ok") { m.call(url) }
        else
          false
        end
      end
      expect { cli.run }.to raise_error(MockSystemExit)
    end

    it "respects starting check index (no-op when > number of checks)" do
      cli = described_class.new(check_num: 3)
      expect { cli.run }.not_to raise_error
    end
  end

  describe "more edge cases for coverage" do
    describe Kettle::Dev::PreReleaseCLI::HTTP do
      it "falls back to URI.parse when Addressable::URI is not defined" do
        url = "http://example.com/x"
        # Temporarily hide Addressable::URI constant if present
        if defined?(Addressable::URI)
          hide_const("Addressable::URI")
        end
        uri = described_class.parse_http_uri(url)
        expect(uri).to be_a(URI::HTTP)
      end

      # rubocop:disable RSpec/VerifiedDoubles
      it "returns false when redirection has no location header" do
        redir = double("Redirection")
        allow(redir).to receive(:is_a?) { |k| k == Net::HTTPRedirection }
        allow(redir).to receive(:[]).with("location").and_return(nil)

        http = double("HTTP")
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:ssl_timeout=)
        allow(http).to receive(:verify_mode=)
        allow(http).to receive_messages(use_ssl?: true, request: redir)
        allow(http).to receive(:start).and_yield(http)

        allow(Net::HTTP).to receive(:new).and_return(http)

        expect(described_class.head_ok?("https://example.com/start")).to be(false)
      end

      it "returns false for non-success, non-redirection, non-method-not-allowed responses" do
        failure = double("Failure")
        allow(failure).to receive(:is_a?).with(Net::HTTPMethodNotAllowed).and_return(false)

        http = double("HTTP")
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:ssl_timeout=)
        allow(http).to receive(:verify_mode=)
        allow(http).to receive_messages(use_ssl?: true, request: failure)
        allow(http).to receive(:start).and_yield(http)

        allow(Net::HTTP).to receive(:new).and_return(http)

        expect(described_class.head_ok?("https://example.org/x")).to be(false)
      end

      it "rescues network errors and returns false" do
        http = double("HTTP")
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:ssl_timeout=)
        allow(http).to receive(:verify_mode=)
        allow(http).to receive(:use_ssl?).and_return(true)
        allow(http).to receive(:start).and_raise(Timeout::Error)

        allow(Net::HTTP).to receive(:new).and_return(http)

        expect(described_class.head_ok?("https://example.org/x")).to be(false)
      end
      # rubocop:enable RSpec/VerifiedDoubles

      it "raises on too many redirects (limit <= 0)" do
        # No Net::HTTP stubbing needed; the error is raised before any network
        expect {
          described_class.head_ok?("https://example.org/x", limit: 0)
        }.to raise_error(ArgumentError, /too many redirects/)
      end
    end

    describe Kettle::Dev::PreReleaseCLI::Markdown do
      it "handles file read errors gracefully and still returns unique urls" do
        Dir.mktmpdir do |root|
          bad = File.join(root, "bad.md")
          File.write(bad, "![x](https://e.com/a.png)\n")
          glob = File.join(root, "*.md")
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(bad).and_raise(Errno::EACCES)

          urls = described_class.extract_image_urls_from_files(glob)
          expect(urls).to eq([])
        end
      end
    end

    describe "check 1 error handling" do
      it "skips files that cannot be read" do
        Dir.mktmpdir do |root|
          good = File.join(root, "good.md")
          bad = File.join(root, "bad.md")
          File.write(good, "# Title\n")
          File.write(bad, "# Bad\n")
          # rubocop:disable ThreadSafety/DirChdir
          Dir.chdir(root) do
            cli = described_class.new(check_num: 1)
            allow(File).to receive(:read).and_call_original
            allow(File).to receive(:read).with(bad).and_raise(Errno::EACCES)
            expect { cli.run }.not_to raise_error
          end
          # rubocop:enable ThreadSafety/DirChdir
        end
      end

      it "warns but continues when write fails for a modified file" do
        Dir.mktmpdir do |root|
          file = File.join(root, "README.md")
          url = "https://img.shields.io/badge/buy_me_a_coffee-\u2713-a51611.svg?style=flat"
          File.write(file, "![x](#{url})\n")
          # rubocop:disable ThreadSafety/DirChdir
          Dir.chdir(root) do
            cli = described_class.new(check_num: 1)
            allow(File).to receive(:write).and_call_original
            allow(File).to receive(:write).with(file, kind_of(String)).and_raise(Errno::EACCES)
            # Avoid running check 2 by stubbing out URLs discovery
            allow(Kettle::Dev::PreReleaseCLI::Markdown).to receive(:extract_image_urls_from_files).and_return([])
            expect { cli.run }.not_to raise_error
          end
          # rubocop:enable ThreadSafety/DirChdir
        end
      end
    end
  end
end
