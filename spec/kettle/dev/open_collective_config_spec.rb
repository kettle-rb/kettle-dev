# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir
RSpec.describe Kettle::Dev::OpenCollectiveConfig do
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
