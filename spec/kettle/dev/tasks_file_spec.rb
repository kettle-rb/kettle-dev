# frozen_string_literal: true

# A tiny unit spec to exercise lib/kettle/dev/tasks.rb so it is covered
# (it registers the gem's rakelib path with Rake when loaded).

require "rake"

RSpec.describe "Kettle::Dev::Tasks file" do # rubocop:disable RSpec/DescribeClass
  it "calls Rake.add_rakelib with the gem's rakelib path" do
    called_with = nil
    allow(Rake).to receive(:add_rakelib) do |arg|
      called_with = arg
    end

    path = File.expand_path("../../..", __dir__)
    file_to_load = File.join(path, "lib", "kettle", "dev", "tasks.rb")

    # load instead of require so the file body executes in spec context
    load(file_to_load)

    expect(Rake).to have_received(:add_rakelib)
    expect(called_with).to end_with("/lib/kettle/dev/rakelib")
  end
end
