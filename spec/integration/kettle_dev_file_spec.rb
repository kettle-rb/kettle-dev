# frozen_string_literal: true

RSpec.describe "kettle-dev file require" do
  it "loads and defines Kettle::Dev" do
    expect { require "kettle-dev" }.not_to raise_error
    expect(defined?(Kettle::Dev)).to eq("constant")
  end
end
