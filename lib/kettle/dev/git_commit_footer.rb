# frozen_string_literal: true

# Keep the class name GitCommitFooter for compatibility with existing hook setups.
# Exposed from lib/ so that exe/kettle-commit-msg can be a minimal wrapper.

class GitCommitFooter
  # Regex to extract `name = "value"` assignments from a gemspec.
  # @return [Regexp]
  NAME_ASSIGNMENT_REGEX = /\bname\s*=\s*(["'])([^"']+)\1/.freeze

  # Whether footer appending is enabled (via GIT_HOOK_FOOTER_APPEND=true)
  # @return [Boolean]
  FOOTER_APPEND = ENV.fetch("GIT_HOOK_FOOTER_APPEND", "false").casecmp("true").zero?
  # The sentinel string that must be present to avoid duplicate footers
  # @return [String, nil]
  SENTINEL = ENV["GIT_HOOK_FOOTER_SENTINEL"]
  raise "Set GIT_HOOK_FOOTER_SENTINEL=<footer sentinel> in .env.local (e.g., '⚡️ A message from a fellow meat-based-AI ⚡️')" if FOOTER_APPEND && (SENTINEL.nil? || SENTINEL.to_s.empty?)

  class << self
    # Resolve git repository top-level dir, or nil outside a repo.
    # @return [String, nil]
    def git_toplevel
      toplevel = nil
      begin
        out = %x(git rev-parse --show-toplevel 2>/dev/null)
        toplevel = out.strip unless out.nil? || out.empty?
      rescue StandardError
      end
      toplevel
    end

    def local_hooks_dir
      top = git_toplevel
      return unless top && !top.empty?
      File.join(top, ".git-hooks")
    end

    def global_hooks_dir
      File.join(ENV["HOME"], ".git-hooks")
    end

    def hooks_path_for(filename)
      local_dir = local_hooks_dir
      if local_dir
        local_path = File.join(local_dir, filename)
        return local_path if File.file?(local_path)
      end
      File.join(global_hooks_dir, filename)
    end

    def commit_goalie_path
      hooks_path_for("commit-subjects-goalie.txt")
    end

    def goalie_allows_footer?(subject_line)
      goalie_path = commit_goalie_path
      return false unless File.file?(goalie_path)

      prefixes = File.read(goalie_path).lines.map { |l| l.strip }.reject { |l| l.empty? || l.start_with?("#") }
      return false if prefixes.empty?

      subj = subject_line.to_s.strip
      prefixes.any? { |prefix| subj.start_with?(prefix) }
    end

    def render(*argv)
      commit_msg = File.read(argv[0])
      subject_line = commit_msg.lines.first.to_s
      if GitCommitFooter::FOOTER_APPEND && goalie_allows_footer?(subject_line)
        if commit_msg.include?(GitCommitFooter::SENTINEL)
          exit(0)
        else
          footer_binding = GitCommitFooter.new
          File.open(argv[0], "w") do |file|
            file.print(commit_msg)
            file.print("\n")
            file.print(footer_binding.render)
          end
        end
      else
        # Skipping footer append
      end
    end
  end

  def initialize
    @pwd = Dir.pwd
    @gemspecs = Dir["*.gemspec"]
    @spec = @gemspecs.first
    @gemspec_path = File.expand_path(@spec, @pwd)
    @gem_name = parse_gemspec_name || derive_gem_name
  end

  def render
    ERB.new(template).result(binding)
  end

  private

  def parse_gemspec_name
    begin
      content = File.read(@gemspec_path)
      @name_index = content =~ NAME_ASSIGNMENT_REGEX
      if @name_index
        return $2
      end
    rescue StandardError
    end
    nil
  end

  def derive_gem_name
    File.basename(@gemspec_path, ".*") if @gemspec_path
  end

  def template
    File.read(self.class.hooks_path_for("footer-template.erb.txt"))
  end
end
