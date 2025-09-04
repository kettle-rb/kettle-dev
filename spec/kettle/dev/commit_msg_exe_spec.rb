# frozen_string_literal: true

require "rbconfig"
require "open3"
require "tmpdir"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "exe/kettle-commit-msg" do
  include_context "with stubbed env"

  it "runs without bundler by only requiring rubygems and kettle/dev" do
    skip_for(reason: "kettle/dev autoload fails under Ruby 2.3 - 2.6 in CI environment; investigate/fix later", versions: %w[2.3 2.4 2.5 2.6])
    Dir.mktmpdir do |dir|
      commit_file = File.join(dir, "COMMIT_EDITMSG")
      File.write(commit_file, "chore: test\n\nbody\n")

      # Ensure script does not try to validate branch or append footer
      stub_env(
        "GIT_HOOK_BRANCH_VALIDATE" => "false",
        "GIT_HOOK_FOOTER_APPEND" => "false",
      )

      ruby = RbConfig.ruby
      cmd = [ruby, File.expand_path("../../../exe/kettle-commit-msg", __dir__), commit_file]

      # Simulate a context where Bundler is not set up; also clear RUBYOPT of -rbundler/setup
      env = {
        "BUNDLE_GEMFILE" => nil,
        "BUNDLE_WITH" => nil,
        "RUBYOPT" => (ENV["RUBYOPT"] || "").split.reject { |opt| opt.include?("bundler/setup") }.join(" "),
      }.reject { |_, v| v.nil? }

      stdout, stderr, status = Open3.capture3(env, *cmd)

      expect(status.exitstatus).to eq(0), "Expected exit 0, got #{status.exitstatus}. stderr: #{stderr}\nstdout: #{stdout}"
      # Should print banner with version loaded from kettle/dev
      expect(stdout).to include("kettle-commit-msg v")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
