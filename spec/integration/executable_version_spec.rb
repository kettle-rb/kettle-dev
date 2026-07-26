# frozen_string_literal: true

require "open3"
require "tmpdir"

RSpec.describe "kettle-dev executables" do
  let(:root) { Kettle::Dev::GEM_ROOT }
  let(:lib_path) { File.join(root, "lib") }
  let(:version) { Kettle::Dev::Version::VERSION }
  let(:executables) do
    Gem::Specification.load(File.join(root, "kettle-dev.gemspec")).executables
  end

  it "prints the shipping gem version for -v and --version" do
    executables.product(%w[-v --version]).each do |executable, flag|
      stdout, stderr, status = run_executable_version(executable, flag)

      expect(status).to be_success, "#{executable} #{flag} failed with stderr: #{stderr}"
      expect(stdout).to eq("#{executable} #{version}\n")
      expect(relevant_stderr(stderr)).to eq("")
    end
  end

  it "wires every packaged executable to the shared header helper" do
    executables.each do |executable|
      source = File.read(File.join(root, "exe", executable))

      expect(source).to include("print_header"), "#{executable} does not use the shared executable header"
    end
  end

  it "does not print the executable header before safe normal output paths by default" do
    safe_commands = {
      "kettle-bump" => ["--help"],
      "kettle-changelog" => ["--help"],
      "kettle-check-eof" => [],
      "kettle-dev-setup" => [],
      "kettle-dvcs" => ["--help"],
      "kettle-gh-release" => ["--help"],
      "kettle-gha-sha-pins" => ["--help"],
      "kettle-pre-release" => ["--help"],
      "kettle-release" => ["--help"]
    }

    Dir.mktmpdir do |empty_root|
      safe_commands.each do |executable, args|
        stdout, stderr, _status = run_executable(executable, args, chdir: empty_root)

        expect(stdout).not_to include("== #{executable} v#{version} =="), "#{executable} printed header; stderr: #{stderr}"
      end
    end
  end

  it "prints the executable header when verbose output is requested" do
    safe_commands = {
      "kettle-bump" => ["--verbose", "--help"],
      "kettle-changelog" => ["--verbose", "--help"],
      "kettle-check-eof" => ["--verbose"],
      "kettle-dev-setup" => ["--verbose"],
      "kettle-dvcs" => ["--verbose", "--help"],
      "kettle-gh-release" => ["--verbose", "--help"],
      "kettle-gha-sha-pins" => ["--verbose", "--help"],
      "kettle-pre-release" => ["--verbose", "--help"],
      "kettle-release" => ["--verbose", "--help"]
    }

    Dir.mktmpdir do |empty_root|
      safe_commands.each do |executable, args|
        stdout, stderr, _status = run_executable(executable, args, chdir: empty_root)

        expect(stdout).to include("== #{executable} v#{version} =="), "#{executable} did not print header; stderr: #{stderr}"
      end
    end
  end

  def run_executable_version(executable, flag)
    run_executable(executable, [flag])
  end

  def run_executable(executable, args, chdir: root)
    path = File.join(root, "exe", executable)
    env = {"RUBYLIB" => lib_path}
    command = if executable.end_with?(".sh")
      [path, *args]
    else
      [RbConfig.ruby, "-I#{lib_path}", path, *args]
    end
    Open3.capture3(env, *command, chdir: chdir)
  end

  def relevant_stderr(stderr)
    stderr.lines.reject { |line| rubygems_platform_warning?(line) }.join
  end

  def rubygems_platform_warning?(line)
    line.include?("warning: already initialized constant Gem::Platform::") ||
      line.include?("warning: previous definition of ")
  end
end
