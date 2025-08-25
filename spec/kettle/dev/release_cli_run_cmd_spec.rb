# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  include_context "with stubbed env"

  let(:cli) { described_class.new }

  describe "#run_cmd! (signing env injection)" do
    it "prefixes SKIP_GEM_SIGNING for 'bundle exec rake build' when env set" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "SKIP_GEM_SIGNING=true bundle exec rake build").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake build")
    end

    it "prefixes SKIP_GEM_SIGNING for 'bundle exec rake release' when env set" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "SKIP_GEM_SIGNING=true bundle exec rake release").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake release")
    end

    it "does not prefix when SKIP_GEM_SIGNING is not set" do
      # ensure var is not present
      stub_env("SKIP_GEM_SIGNING" => nil)
      expect(cli).to receive(:system).with(kind_of(Hash), "bundle exec rake build").and_return(true)
      cli.send(:run_cmd!, "bundle exec rake build")
    end

    it "does not prefix unrelated commands" do
      stub_env("SKIP_GEM_SIGNING" => "true")
      expect(cli).to receive(:system).with(kind_of(Hash), "bin/rake").and_return(true)
      cli.send(:run_cmd!, "bin/rake")
    end
  end
end
