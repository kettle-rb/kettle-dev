# frozen_string_literal: true

RSpec.describe Kettle::Dev::OpenCollectiveConfig do
  include_context "with stubbed env"

  describe "::yaml_path" do
    it "returns an absolute path ending with .opencollective.yml" do
      path = described_class.yaml_path
      expect(path).to be_a(String)
      expect(Pathname.new(path)).to be_absolute
      expect(path).to end_with("/.opencollective.yml")
    end
  end

  describe "::handle" do
    let(:tmp_yaml) { File.join(Dir.mktmpdir, ".opencollective.yml") }

    before do
      # Default: no env
      stub_env("OPENCOLLECTIVE_HANDLE" => nil)
      # Point yaml_path to our temp file unless a case wants real path
      allow(described_class).to receive(:yaml_path).and_return(tmp_yaml)
      FileUtils.rm_f(tmp_yaml)
    end

    after do
      FileUtils.rm_f(tmp_yaml)
    end

    it "prefers ENV over YAML when both are present" do
      File.write(tmp_yaml, "collective: from-file\n")
      stub_env("OPENCOLLECTIVE_HANDLE" => "from-env")
      expect(described_class.handle(required: false)).to eq("from-env")
    end

    it "reads the 'collective' key from YAML when ENV is missing" do
      File.write(tmp_yaml, "collective: kettle-rb\n")
      expect(described_class.handle(required: false)).to eq("kettle-rb")
    end

    it "returns nil when not required and neither ENV nor YAML provide a handle" do
      # No env, no file
      expect(described_class.handle(required: false)).to be_nil
    end

    it "aborts via ExitAdapter when required and not discoverable", :real_exit_adapter do
      # No env, no file
      allow(Kettle::Dev::ExitAdapter).to receive(:abort).and_raise(SystemExit.new(1))
      expect { described_class.handle(required: true) }.to raise_error(SystemExit)
    end

    it "logs YAML read/parse errors and returns nil when not required" do
      File.write(tmp_yaml, "collective: ok\n")
      allow(File).to receive(:read).with(tmp_yaml).and_raise(StandardError.new("boom"))
      allow(Kettle::Dev).to receive(:debug_error)

      expect(described_class.handle(required: false)).to be_nil
      expect(Kettle::Dev).to have_received(:debug_error)
    end

    it "logs YAML read/parse errors and aborts when required", :real_exit_adapter do
      File.write(tmp_yaml, "collective: ok\n")
      allow(File).to receive(:read).with(tmp_yaml).and_raise(StandardError.new("boom"))
      allow(Kettle::Dev).to receive(:debug_error)
      allow(Kettle::Dev::ExitAdapter).to receive(:abort).and_raise(SystemExit.new(1))

      expect { described_class.handle(required: true) }.to raise_error(SystemExit)
      expect(Kettle::Dev).to have_received(:debug_error)
    end
  end
end
