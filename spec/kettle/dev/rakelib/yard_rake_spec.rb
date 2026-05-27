# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake yard" do
  around do |example|
    previous = Rake.application
    defaults = Kettle::Dev.defaults
    Rake.application = Rake::Application.new
    Kettle::Dev.instance_variable_set(:@defaults, [].freeze)
    Rake::Task.define_task(:default)
    example.run
  ensure
    Rake.application = previous
    Kettle::Dev.instance_variable_set(:@defaults, defaults)
  end

  before do
    rakelib = File.expand_path("../../../../lib/kettle/dev/rakelib", __dir__)
    Rake.application.rake_require("yard", [rakelib], $".reject { |file| file == File.join(rakelib, "yard.rake") })
  end

  it "registers yard as a default task" do
    expect(Kettle::Dev.defaults).to include("yard")
    expect(Rake::Task[:default].prerequisites).to include("yard")
  end
end
