# frozen_string_literal: true

require "open3"

RSpec.describe "kettle-dev executables" do
  let(:root) { Kettle::Dev::GEM_ROOT }
  let(:lib_path) { File.join(root, "lib") }
  let(:version) { Kettle::Dev::Version::VERSION }
  let(:executables) do
    %w[
      kettle-bump
      kettle-changelog
      kettle-check-eof
      kettle-check-eof.sh
      kettle-commit-msg
      kettle-dev-setup
      kettle-dvcs
      kettle-gh-release
      kettle-gha-sha-pins
      kettle-pre-release
      kettle-readme-backers
      kettle-release
    ]
  end

  it "prints the shipping gem version for -v and --version" do
    executables.product(%w[-v --version]).each do |executable, flag|
      stdout, stderr, status = run_executable_version(executable, flag)

      expect(status).to be_success, "#{executable} #{flag} failed with stderr: #{stderr}"
      expect(stdout).to eq("#{executable} #{version}\n")
      expect(stderr).to eq("")
    end
  end

  def run_executable_version(executable, flag)
    path = File.join(root, "exe", executable)
    env = {"RUBYLIB" => lib_path}
    command = if executable.end_with?(".sh")
      [path, flag]
    else
      [RbConfig.ruby, "-I#{lib_path}", path, flag]
    end
    Open3.capture3(env, *command, chdir: root)
  end
end
