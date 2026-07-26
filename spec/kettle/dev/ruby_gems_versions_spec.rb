# frozen_string_literal: true

require "tmpdir"
require "kettle/dev/ruby_gems_versions"

RSpec.describe Kettle::Dev::RubyGemsVersions do
  def ok_response(body)
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = body
    response
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @cache_bust_path = File.join(dir, "rubygems-cache-bust.json")
      example.run
    end
  end

  before do
    stub_env("KETTLE_RUBYGEMS_CACHE_BUST_PATH" => @cache_bust_path, "KETTLE_RUBYGEMS_REFRESH" => nil)
  end

  it "records recently published gem versions in a best-effort marker file", freeze: Time.utc(2026, 7, 21, 12, 0, 0) do
    described_class.mark_released("demo", "1.2.3")

    marker = JSON.parse(File.read(@cache_bust_path))
    expect(marker.dig("releases", "demo")).to eq(
      "version" => "1.2.3",
      "released_at" => "2026-07-21T12:00:00Z"
    )
  end

  it "cache-busts version lookups for freshly published matching gem versions", freeze: Time.utc(2026, 7, 21, 12, 5, 0) do
    write_marker("demo", "1.2.3", "2026-07-21T12:00:00Z")
    response = ok_response(JSON.generate([{"number" => "1.2.3"}]))
    request_uri = nil
    request_headers = nil
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |request|
      request_uri = request.uri
      request_headers = request.to_hash
      response
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)

    versions = described_class.fetch("demo", version_hint: "1.2.3")

    expect(versions).to eq([{"number" => "1.2.3"}])
    expect(request_uri.query).to include("_kettle_cache_bust=")
    expect(request_headers.fetch("cache-control")).to eq(["no-cache"])
    expect(request_headers.fetch("pragma")).to eq(["no-cache"])
  end

  it "uses normal version lookup URLs outside the marker freshness window", freeze: Time.utc(2026, 7, 21, 12, 16, 0) do
    write_marker("demo", "1.2.3", "2026-07-21T12:00:00Z")
    response = ok_response(JSON.generate([]))
    request_uri = nil
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |request|
      request_uri = request.uri
      response
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)

    described_class.fetch("demo", version_hint: "1.2.3")

    expect(request_uri.query).to be_nil
  end

  def write_marker(gem_name, version, released_at)
    File.write(
      @cache_bust_path,
      JSON.generate("releases" => {gem_name => {"version" => version, "released_at" => released_at}})
    )
  end
end
