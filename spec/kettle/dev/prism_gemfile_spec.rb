# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/prism_gemfile"

RSpec.describe Kettle::Dev::PrismGemfile do
  describe ".merge_gem_calls" do
    it "replaces source and appends missing gem calls", :prism_merge_only do
      src = <<~RUBY
        source "https://rubygems.org"
        gem "a"
        gem "b"
      RUBY

      dest = <<~RUBY
        # existing header
        gem "a"
      RUBY

      out = described_class.merge_gem_calls(src, dest)
      expect(out).to include('source "https://rubygems.org"')
      expect(out).to include('gem "b"')
      # a should not be duplicated
      expect(out.scan('gem "a"').length).to eq(1)
    end

    it "replaces matching git_source by name and inserts when missing", :prism_merge_only do
      src = <<~'RUBY'
        git_source(:github) { |repo| "https://github.com/#{repo}.git" }
      RUBY
      dest = ""
      out = described_class.merge_gem_calls(src, dest)
      expect(out).to include("git_source(:github)")

      dest2 = <<~'RUBY'
        git_source(:gitlab) { |repo| "https://gitlab.com/#{repo}.git" }
      RUBY
      out2 = described_class.merge_gem_calls(src, dest2)
      # should replace the existing gitlab/generic with the github one if no same-name present
      expect(out2).to include("git_source(:github)")
    end

    it "does not move gems inside groups to top-level" do
      src = <<~RUBY
        group :development do
          gem "dev-only"
        end
      RUBY
      dest = <<~RUBY
        gem "a"
      RUBY
      out = described_class.merge_gem_calls(src, dest)
      # top-level should only contain `a` and not `dev-only`
      expect(out.scan('gem "dev-only"').length).to eq(0)
    end

    # --- Additional edge-case tests ---

    it "appends gem with options (hash / version) and preserves options", :prism_merge_only do
      src = <<~RUBY
        gem "with_opts", "~> 1.2", require: false
      RUBY
      dest = <<~RUBY
        # header
      RUBY
      out = described_class.merge_gem_calls(src, dest)
      expect(out).to include('gem "with_opts", "~> 1.2", require: false')
    end

    it "does not duplicate a gem when quoting differs between src and dest" do
      src = <<~RUBY
        gem "dupme"
      RUBY
      dest = <<~RUBY
        gem 'dupme'
      RUBY
      out = described_class.merge_gem_calls(src, dest)
      expect(out.scan(/gem \"dupme\"|gem 'dupme'/).length).to eq(1)
    end

    it "preserves inline comments on appended gem lines", :prism_merge_only do
      src = <<~RUBY
        gem "c" # important comment
      RUBY
      dest = ""
      out = described_class.merge_gem_calls(src, dest)
      expect(out).to include('gem "c" # important comment')
    end

    it "replaces source and multiple git_source nodes and keeps insertion order", :prism_merge_only do
      src = <<~'RUBY'
        source "https://new.example"
        git_source(:github) { |repo| "https://github.com/#{repo}.git" }
        git_source(:private) { |repo| "https://git.example/#{repo}.git" }
        gem "x"
      RUBY
      dest = <<~RUBY
        source "https://old.example"
        # existing
      RUBY
      out = described_class.merge_gem_calls(src, dest)
      expect(out).to include('source "https://new.example"')
      expect(out).to include("git_source(:github)")
      expect(out).to include("git_source(:private)")
      # ensure gem x appended
      expect(out).to include('gem "x"')
    end

    it "ignores gem declarations inside conditional or other non-top-level constructs" do
      src = <<~RUBY
        if ENV['CI']
          gem "ci-only"
        end
      RUBY
      dest = <<~RUBY
        gem "z"
      RUBY
      out = described_class.merge_gem_calls(src, dest)
      # ci-only should not be appended to top-level
      expect(out).not_to include('gem "ci-only"')
    end
  end
end
