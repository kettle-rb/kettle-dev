# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir
RSpec.describe Kettle::Dev::OpenCollectiveConfig do
  describe "::disabled?" do
    before do
      hide_env("OPENCOLLECTIVE_HANDLE", "FUNDING_ORG")
    end

    context "when neither variable is set" do
      it "returns false" do
        expect(described_class.disabled?).to be(false)
      end
    end

    context "when OPENCOLLECTIVE_HANDLE is a falsey value" do
      %w[false FALSE False no NO No n N 0].each do |val|
        it "returns true for #{val.inspect}" do
          stub_env("OPENCOLLECTIVE_HANDLE" => val)

          expect(described_class.disabled?).to be(true)
        end
      end
    end

    context "when FUNDING_ORG is a falsey value" do
      %w[false FALSE False no NO No n N 0].each do |val|
        it "returns true for #{val.inspect}" do
          stub_env("FUNDING_ORG" => val)

          expect(described_class.disabled?).to be(true)
        end
      end
    end

    context "when both variables are set to falsey values" do
      it "returns true" do
        stub_env("OPENCOLLECTIVE_HANDLE" => "false", "FUNDING_ORG" => "no")

        expect(described_class.disabled?).to be(true)
      end
    end

    context "when falsey value has surrounding whitespace" do
      %w[false no 0 n].each do |val|
        it "returns true for #{("  #{val}  ").inspect}" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "  #{val}  ")

          expect(described_class.disabled?).to be(true)
        end
      end
    end

    context "when variable is set to a truthy or non-falsey value" do
      %w[true TRUE yes YES y Y 1 kettle-rb some-handle].each do |val|
        it "returns false for #{val.inspect}" do
          stub_env("OPENCOLLECTIVE_HANDLE" => val)

          expect(described_class.disabled?).to be(false)
        end
      end
    end

    context "when variable is set to empty string" do
      it "returns false for OPENCOLLECTIVE_HANDLE" do
        stub_env("OPENCOLLECTIVE_HANDLE" => "")

        expect(described_class.disabled?).to be(false)
      end

      it "returns false for FUNDING_ORG" do
        stub_env("FUNDING_ORG" => "")

        expect(described_class.disabled?).to be(false)
      end
    end

    context "when only one variable is falsey and the other is truthy" do
      it "returns true when OPENCOLLECTIVE_HANDLE is falsey and FUNDING_ORG is truthy" do
        stub_env("OPENCOLLECTIVE_HANDLE" => "false", "FUNDING_ORG" => "kettle-rb")

        expect(described_class.disabled?).to be(true)
      end

      it "returns true when FUNDING_ORG is falsey and OPENCOLLECTIVE_HANDLE is truthy" do
        stub_env("OPENCOLLECTIVE_HANDLE" => "kettle-rb", "FUNDING_ORG" => "0")

        expect(described_class.disabled?).to be(true)
      end
    end

    context "when variable is whitespace-only" do
      it "returns false for OPENCOLLECTIVE_HANDLE" do
        stub_env("OPENCOLLECTIVE_HANDLE" => "   ")

        expect(described_class.disabled?).to be(false)
      end
    end
  end

  describe "::handle" do
    around do |ex|
      Dir.mktmpdir do |dir|
        @dir = dir
        Dir.chdir(dir) { ex.run }
      end
    end

    before do
      # Ensure ENV does not short‑circuit YAML lookup
      stub_env("OPENCOLLECTIVE_HANDLE" => nil)
    end

    it "returns the 'collective' value in strict mode when present" do
      File.write(".opencollective.yml", "collective: kettle-dev\n")

      result = described_class.handle(strict: true, root: @dir)

      expect(result).to eq("kettle-dev")
    end

    it "falls back to 'org' value in strict mode when 'collective' is absent" do
      File.write(".opencollective.yml", "org: acme-inc\n")

      result = described_class.handle(strict: true, root: @dir)

      expect(result).to eq("acme-inc")
    end

    it "returns nil in strict mode when value is blank and required is false" do
      File.write(".opencollective.yml", "collective: '  '\n")

      result = described_class.handle(strict: true, root: @dir, required: false)

      expect(result).to be_nil
    end
  end
end
# rubocop:enable ThreadSafety/DirChdir
