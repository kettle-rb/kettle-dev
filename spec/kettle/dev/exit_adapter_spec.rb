# frozen_string_literal: true

RSpec.describe "::ExitAdapter" do
  it "raises SystemExit with message via abort" do
    expect {
      Kettle::Dev::ExitAdapter.abort("boom")
    }.to raise_error(SystemExit) # message goes to STDERR via Kernel.abort
  end

  it "raises SystemExit with status via exit" do
    begin
      Kettle::Dev::ExitAdapter.exit(3)
    rescue SystemExit => e
      expect(e.status).to eq(3)
    end
  end
end
