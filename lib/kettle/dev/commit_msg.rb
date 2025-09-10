# frozen_string_literal: true

# Branch rule enforcement and commit message footer support for commit-msg hook.
# Provides a lib entrypoint so the exe wrapper can be minimal.

module Kettle
  module Dev
    module CommitMsg
      module_function

      BRANCH_RULES = {
        "jira" => /^(?<story_type>(hotfix)|(bug)|(feature)|(candy))\/(?<story_id>\d{8,})-.+\Z/,
      }.freeze

      # Enforce branch rule by appending [type][id] to the commit message when missing.
      # @param path [String] path to commit message file (ARGV[0] from git)
      def enforce_branch_rule!(path)
        validate = ENV.fetch("GIT_HOOK_BRANCH_VALIDATE", "false")
        branch_rule_type = (!validate.casecmp("false").zero? && validate) || nil
        return unless branch_rule_type

        branch_rule = BRANCH_RULES[branch_rule_type]
        return unless branch_rule

        branch = %x(git branch 2> /dev/null | grep -e ^* | awk '{print $2}')
        match_data = branch.match(branch_rule)
        return unless match_data

        commit_msg = File.read(path)
        unless commit_msg.include?(match_data[:story_id])
          commit_msg = <<~EOS
            #{commit_msg.strip}
            [#{match_data[:story_type]}][#{match_data[:story_id]}]
          EOS
          File.open(path, "w") { |file| file.print(commit_msg) }
        end
      end
    end
  end
end
