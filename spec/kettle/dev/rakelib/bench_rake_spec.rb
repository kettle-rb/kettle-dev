# frozen_string_literal: true

require "spec_helper"

RSpec.describe "bench rake tasks" do # rubocop:disable RSpec/DescribeClass
  let(:rakelib) { File.expand_path("../../../../lib/kettle/dev/rakelib", __dir__) }
  let(:bench_glob) { File.join(rakelib, "benchmarks", "*.rb") }
  let(:bench_script) { File.join(rakelib, "benchmarks", "example.rb") }

  around do |example|
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = previous_application
    end
  end

  def load_bench_tasks
    load File.join(rakelib, "bench.rake")
  end

  def stub_bench_files(files)
    allow(Dir).to receive(:[]).and_call_original
    allow(Dir).to receive(:[]).with(File.join(rakelib, "benchmarks")).and_return(files)
    allow(Dir).to receive(:[]).with(bench_glob).and_return(files)
  end

  it "lists that no benchmark scripts are present" do
    stub_bench_files([])

    load_bench_tasks

    expect { Rake::Task["bench:list"].invoke }.to output(/No benchmark scripts found/).to_stdout
  end

  it "lists benchmark script basenames" do
    stub_bench_files([bench_script])

    load_bench_tasks

    expect { Rake::Task["bench:list"].invoke }.to output("example.rb\n").to_stdout
  end

  it "skips benchmark execution on CI" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CI", "false").and_return("true")

    load_bench_tasks

    expect { Rake::Task["bench:run"].invoke }.to output(/disabled on CI/).to_stdout
  end

  it "reports that there are no benchmark scripts to run" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CI", "false").and_return("false")
    stub_bench_files([])

    load_bench_tasks

    expect { Rake::Task["bench:run"].invoke }.to output(/No benchmark scripts found/).to_stdout
  end

  it "runs benchmarks through bundler when BENCH_BUNDLER is enabled" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CI", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("BENCH_BUNDLER", "0").and_return("1")
    stub_bench_files([bench_script])
    allow(RbConfig).to receive(:ruby).and_return("ruby")
    allow_any_instance_of(Object).to receive(:system).with("bundle", "exec", "ruby", "-Ilib", bench_script).and_return(true) # rubocop:disable RSpec/AnyInstance

    load_bench_tasks

    expect { Rake::Task["bench:run"].invoke }.to output(/Running: example\.rb/).to_stdout
  end

  it "runs benchmarks inside Bundler.with_unbundled_env when Bundler is available" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("CI", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("BENCH_BUNDLER", "0").and_return("0")
    stub_bench_files([bench_script])
    allow(RbConfig).to receive(:ruby).and_return("ruby")
    allow(Bundler).to receive(:with_unbundled_env).and_yield
    allow_any_instance_of(Object).to receive(:system).with("ruby", "-Ilib", bench_script).and_return(true) # rubocop:disable RSpec/AnyInstance

    load_bench_tasks

    expect { Rake::Task["bench:run"].invoke }.to output(/Running: example\.rb/).to_stdout
  end

  it "aliases bench to bench:run" do
    load_bench_tasks

    expect(Rake::Task[:bench].prerequisites).to eq(["bench:run"])
  end
end
