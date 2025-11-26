# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/prism_gemspec"

RSpec.describe Kettle::Dev::PrismGemspec do
  describe ".replace_gemspec_fields" do
    it "replaces scalar fields inside gemspec block and preserves comments" do
      src = <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          # original comment
          spec.name = "kettle-dev"
          spec.version = "0.1.0"
          spec.authors = ["Old Author"]

          # keep me
          spec.add_dependency "rake"
        end
      RUBY

      out = described_class.replace_gemspec_fields(src, {name: "my-gem", authors: ["A", "B"]})
      expect(out).to include('spec.name = "my-gem"')
      expect(out).to include('spec.authors = ["A", "B"]')
      # ensure comment preserved
      expect(out).to include("# original comment")
    end

    it "removes self-dependency when _remove_self_dependency provided" do
      src = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "kettle-dev"
          spec.add_dependency "kettle-dev", "~> 1.0"
          spec.add_development_dependency 'other'
        end
      RUBY

      out = Kettle::Dev::PrismGemspec.replace_gemspec_fields(src, {_remove_self_dependency: "kettle-dev"})
      expect(out).not_to include('add_dependency "kettle-dev"')
      expect(out).to include("add_development_dependency")
    end

    it "handles a different block param name" do
      src = <<~RUBY
        Gem::Specification.new do |s|
          s.name = "old"
        end
      RUBY
      out = described_class.replace_gemspec_fields(src, {name: "new"})
      expect(out).to include('s.name = "new"')
    end

    it "inserts field after version when version not present" do
      src = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "a"
        end
      RUBY
      out = described_class.replace_gemspec_fields(src, {authors: ["X"]})
      expect(out).to include('spec.authors = ["X"]')
    end

    it "preserves commented out dependency lines and does not remove them" do
      src = <<~RUBY
        Gem::Specification.new do |spec|
          # spec.add_dependency "kettle-dev", "~> 1"
          spec.add_dependency "other"
        end
      RUBY
      out = described_class.replace_gemspec_fields(src, {_remove_self_dependency: "kettle-dev"})
      expect(out).to include('# spec.add_dependency "kettle-dev"')
      expect(out).to include('spec.add_dependency "other"')
    end

    it "does not replace non-literal RHS assignments" do
      src = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = generate_name
        end
      RUBY
      out = described_class.replace_gemspec_fields(src, {name: "x"})
      expect(out).to include("spec.name = generate_name")
      expect(out).not_to include('spec.name = "x"')
    end
  end
end
