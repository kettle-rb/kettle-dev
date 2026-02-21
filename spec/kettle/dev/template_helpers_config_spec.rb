# frozen_string_literal: true

RSpec.describe Kettle::Dev::TemplateHelpers do
  # Reset memoized config between tests
  before do
    described_class.class_variable_set(:@@kettle_config, nil)
    described_class.class_variable_set(:@@manifestation, nil)
  end

  describe ".kettle_config" do
    it "loads the .kettle-dev.yml configuration file" do
      config = described_class.kettle_config
      expect(config).to be_a(Hash)
      expect(config).to have_key("defaults")
      expect(config).to have_key("patterns")
      expect(config).to have_key("files")
    end

    it "returns defaults with expected merge options" do
      defaults = described_class.kettle_config["defaults"]
      expect(defaults["preference"]).to eq("template")
      expect(defaults["add_template_only_nodes"]).to be(true)
      expect(defaults["freeze_token"]).to eq("kettle-dev")
    end
  end

  describe ".strategy_for" do
    let(:project_root) { described_class.project_root }

    context "when file is explicitly listed in files section" do
      it "returns :merge for Gemfile" do
        path = File.join(project_root, "Gemfile")
        expect(described_class.strategy_for(path)).to eq(:merge)
      end

      it "returns :merge for Rakefile" do
        path = File.join(project_root, "Rakefile")
        expect(described_class.strategy_for(path)).to eq(:merge)
      end

      it "returns :skip for .gitignore" do
        path = File.join(project_root, ".gitignore")
        expect(described_class.strategy_for(path)).to eq(:skip)
      end

      it "returns :skip for nested file .github/workflows/style.yml" do
        path = File.join(project_root, ".github/workflows/style.yml")
        expect(described_class.strategy_for(path)).to eq(:skip)
      end

      it "returns :merge for nested file gemfiles/modular/coverage.gemfile" do
        path = File.join(project_root, "gemfiles/modular/coverage.gemfile")
        expect(described_class.strategy_for(path)).to eq(:merge)
      end
    end

    context "when file matches a glob pattern" do
      it "returns :merge for any .gemspec file via glob" do
        path = File.join(project_root, "my-gem.gemspec")
        expect(described_class.strategy_for(path)).to eq(:merge)
      end

      it "returns :merge for deeply nested erb gemfile via glob" do
        path = File.join(project_root, "gemfiles/modular/erb/r2/v3.0.gemfile")
        expect(described_class.strategy_for(path)).to eq(:merge)
      end

      it "returns :skip for unknown .github yml via glob" do
        path = File.join(project_root, ".github/workflows/unknown.yml")
        expect(described_class.strategy_for(path)).to eq(:skip)
      end
    end

    context "when file is not found in config" do
      it "returns :skip for completely unknown file" do
        path = File.join(project_root, "some/random/unknown_file.txt")
        expect(described_class.strategy_for(path)).to eq(:skip)
      end
    end
  end

  describe ".config_for" do
    it "returns config with merge options for Gemfile" do
      config = described_class.config_for("Gemfile")
      expect(config[:strategy]).to eq(:merge)
      expect(config[:preference]).to eq("template")
      expect(config[:add_template_only_nodes]).to be(true)
      expect(config[:freeze_token]).to eq("kettle-dev")
    end

    it "returns config without merge options for skip strategy" do
      config = described_class.config_for(".gitignore")
      expect(config[:strategy]).to eq(:skip)
      expect(config).not_to have_key(:preference)
    end

    it "prefers explicit file config over pattern match" do
      # .github/workflows/style.yml is both in files section AND matches .github/**/*.yml pattern
      config = described_class.config_for(".github/workflows/style.yml")
      expect(config[:strategy]).to eq(:skip)
      # Should come from files section (no :path key) not patterns
      expect(config).not_to have_key(:path)
    end

    it "falls back to pattern when file not explicitly listed" do
      config = described_class.config_for("brand-new.gemspec")
      expect(config[:strategy]).to eq(:merge)
      expect(config[:path]).to eq("*.gemspec")
    end

    it "returns nil for unknown file" do
      config = described_class.config_for("totally/unknown/path.xyz")
      expect(config).to be_nil
    end
  end

  describe ".find_file_config" do
    it "navigates nested structure to find config" do
      config = described_class.find_file_config("gemfiles/modular/erb/r2/v3.0.gemfile")
      expect(config).to be_a(Hash)
      expect(config[:strategy]).to eq(:merge)
    end

    it "returns nil for partial path that is a directory" do
      config = described_class.find_file_config("gemfiles/modular")
      expect(config).to be_nil
    end

    it "returns nil for path not in files section" do
      config = described_class.find_file_config("nonexistent/file.rb")
      expect(config).to be_nil
    end
  end

  describe ".load_manifest" do
    it "returns array of pattern entries" do
      manifest = described_class.load_manifest
      expect(manifest).to be_an(Array)
      expect(manifest).not_to be_empty
    end

    it "each entry has :path and :strategy" do
      manifest = described_class.load_manifest
      expect(manifest).to all(have_key(:path).and(have_key(:strategy)))
    end

    it "merge strategy entries include default merge options" do
      manifest = described_class.load_manifest
      merge_entry = manifest.find { |e| e[:strategy] == :merge }
      expect(merge_entry).not_to be_nil
      expect(merge_entry[:preference]).to eq("template")
      expect(merge_entry[:add_template_only_nodes]).to be(true)
    end
  end
end
