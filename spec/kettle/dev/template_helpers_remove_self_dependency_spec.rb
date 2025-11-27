# frozen_string_literal: true

RSpec.describe Kettle::Dev::TemplateHelpers, ".remove_self_dependency" do
  let(:gem_name) { "my-gem" }

  describe "gemspec files" do
    it "removes self-dependency from gemspec" do
      content = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.add_dependency "my-gem", "~> 1.0"
          spec.add_dependency "rails"
        end
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "my-gem.gemspec")
      expect(out).not_to include('add_dependency "my-gem"')
      expect(out).to include('add_dependency "rails"')
    end
  end

  describe "Gemfile files" do
    it "removes self-dependency from Gemfile" do
      content = <<~RUBY
        gem "rails"
        gem "my-gem"
        gem "rspec"
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "Gemfile")
      expect(out).not_to include('gem "my-gem"')
      expect(out).to include('gem "rails"')
      expect(out).to include('gem "rspec"')
    end
  end

  describe "Appraisal.root.gemfile files" do
    it "removes self-dependency from Appraisal.root.gemfile" do
      content = <<~RUBY
        gem "bundler"
        gem "my-gem"
        gem "rake"
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "Appraisal.root.gemfile")
      expect(out).not_to include('gem "my-gem"')
      expect(out).to include('gem "bundler"')
      expect(out).to include('gem "rake"')
    end
  end

  describe "modular gemfile files" do
    it "removes self-dependency from coverage.gemfile" do
      content = <<~RUBY
        gem "simplecov"
        gem "my-gem"
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "gemfiles/modular/coverage.gemfile")
      expect(out).not_to include('gem "my-gem"')
      expect(out).to include('gem "simplecov"')
    end

    it "removes self-dependency from style.gemfile" do
      content = <<~RUBY
        gem "rubocop"
        gem "my-gem"
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "gemfiles/modular/style.gemfile")
      expect(out).not_to include('gem "my-gem"')
      expect(out).to include('gem "rubocop"')
    end
  end

  describe "Appraisals files" do
    it "removes self-dependency from Appraisals" do
      content = <<~RUBY
        appraise("rails-7") {
          gem "rails", "~> 7.0"
          gem "my-gem"
        }
      RUBY

      out = described_class.remove_self_dependency(content, gem_name, "Appraisals")
      expect(out).not_to include('gem "my-gem"')
      expect(out).to include('gem "rails"')
    end
  end

  describe "unknown file types" do
    it "returns content unchanged for non-gem files" do
      content = "some content"
      out = described_class.remove_self_dependency(content, gem_name, "README.md")
      expect(out).to eq(content)
    end
  end

  describe "edge cases" do
    it "returns content unchanged when gem_name is empty" do
      content = 'gem "foo"'
      out = described_class.remove_self_dependency(content, "", "Gemfile")
      expect(out).to eq(content)
    end

    it "returns content unchanged when gem_name is nil" do
      content = 'gem "foo"'
      out = described_class.remove_self_dependency(content, nil, "Gemfile")
      expect(out).to eq(content)
    end
  end
end
