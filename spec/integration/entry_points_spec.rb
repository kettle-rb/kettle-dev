# frozen_string_literal: true

RSpec.describe "entry points" do
  it "loads via require 'kettle/dev' and exposes APIs" do
    expect { require "kettle/dev" }.not_to raise_error
    expect(defined?(Kettle::Dev)).to eq("constant")
    expect(defined?(Kettle::Dev::CIHelpers)).to eq("constant")
  end

  it "loads via require 'kettle-dev' and exposes APIs" do
    expect { require "kettle-dev" }.not_to raise_error
    expect(defined?(Kettle::Dev)).to eq("constant")
    expect(defined?(Kettle::Dev::CIHelpers)).to eq("constant")
  end
end
