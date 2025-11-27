# frozen_string_literal: true

RSpec.describe Kettle::Dev::PrismAppraisals, ".remove_gem_dependency" do
  describe "removing self-referential gem dependencies from appraise blocks" do
    it "removes gem call matching the gem name from appraise blocks" do
      src = <<~RUBY
        appraise("rails-7") {
          gem "rails", "~> 7.0"
          gem "my-gem", "~> 1.0"
          gem "rspec"
        }
      RUBY

      out = described_class.remove_gem_dependency(src, "my-gem")
      expect(out).to include('gem "rails"')
      expect(out).to include('gem "rspec"')
      expect(out).not_to include('gem "my-gem"')
    end

    it "removes self-dependency from multiple appraise blocks" do
      src = <<~RUBY
        appraise("rails-6") {
          gem "rails", "~> 6.0"
          gem "my-gem"
        }

        appraise("rails-7") {
          gem "rails", "~> 7.0"
          gem "my-gem"
        }
      RUBY

      out = described_class.remove_gem_dependency(src, "my-gem")
      expect(out).to include('gem "rails", "~> 6.0"')
      expect(out).to include('gem "rails", "~> 7.0"')
      expect(out).not_to include('gem "my-gem"')
    end

    it "returns content unchanged when gem_name is empty" do
      src = <<~RUBY
        appraise("test") {
          gem "foo"
        }
      RUBY

      out = described_class.remove_gem_dependency(src, "")
      expect(out).to eq(src)
    end

    it "preserves comments and structure when removing gem" do
      src = <<~RUBY
        # Rails 7 appraisal
        appraise("rails-7") {
          gem "rails", "~> 7.0"
          gem "my-app"
          gem "rspec" # Testing
        }
      RUBY

      out = described_class.remove_gem_dependency(src, "my-app")
      expect(out).to include("# Rails 7 appraisal")
      expect(out).to include('gem "rails"')
      expect(out).to include('gem "rspec"')
      expect(out).not_to include('gem "my-app"')
    end
  end
end
