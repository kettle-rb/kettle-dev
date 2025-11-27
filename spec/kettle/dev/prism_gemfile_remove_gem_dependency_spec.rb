# frozen_string_literal: true

RSpec.describe Kettle::Dev::PrismGemfile, ".remove_gem_dependency" do
  describe "removing self-referential gem dependencies" do
    it "removes gem call matching the gem name" do
      src = <<~RUBY
        source "https://rubygems.org"
        
        gem "rails", "~> 7.0"
        gem "my-gem", "~> 1.0"
        gem "other-gem"
      RUBY

      out = described_class.remove_gem_dependency(src, "my-gem")
      expect(out).to include('gem "rails"')
      expect(out).to include('gem "other-gem"')
      expect(out).not_to include('gem "my-gem"')
    end

    it "preserves other gem calls when removing self-dependency" do
      src = <<~RUBY
        gem "my-app"
        gem "rspec"
        gem "rubocop"
      RUBY

      out = described_class.remove_gem_dependency(src, "my-app")
      expect(out).not_to include('gem "my-app"')
      expect(out).to include('gem "rspec"')
      expect(out).to include('gem "rubocop"')
    end

    it "returns content unchanged when gem_name is empty" do
      src = 'gem "foo"'
      out = described_class.remove_gem_dependency(src, "")
      expect(out).to eq(src)
    end

    it "handles modular gemfile content" do
      src = <<~RUBY
        # Coverage tools
        gem "simplecov", "~> 0.22"
        gem "my-gem", require: false
      RUBY

      out = described_class.remove_gem_dependency(src, "my-gem")
      expect(out).to include("simplecov")
      expect(out).not_to include('gem "my-gem"')
    end
  end
end
