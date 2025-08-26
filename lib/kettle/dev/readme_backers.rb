# frozen_string_literal: true

# External stdlib
require "yaml"
require "json"
require "uri"
require "net/http"
require "set"

module Kettle
  module Dev
    class ReadmeBackers
      DEFAULT_AVATAR = "https://opencollective.com/static/images/default-avatar.png"
      README_PATH = File.expand_path("../../../../README.md", __dir__)
      OC_YML_PATH = File.expand_path("../../../../.opencollective.yml", __dir__)
      README_OSC_TAG_DEFAULT = "OPENCOLLECTIVE"
      COMMIT_SUBJECT_DEFAULT = "💸 Thanks 🙏 to our new backers 🎒 and subscribers 📜"

      # Ruby 2.3 compatibility: Struct keyword_init added in Ruby 2.5
      # Switch to struct when dropping ruby < 2.5
      # Backer = Struct.new(:name, :image, :website, :profile, keyword_init: true)
      # Fallback for Ruby < 2.5 where Struct keyword_init is unsupported
      class Backer
        attr_accessor :name, :image, :website, :profile

        def initialize(name: nil, image: nil, website: nil, profile: nil, **_ignored)
          @name = name
          @image = image
          @website = website
          @profile = profile
        end
      end

      def initialize(handle: nil, readme_path: README_PATH)
        @handle = handle || resolve_handle
        @readme_path = readme_path
      end

      def run!
        readme = File.read(@readme_path)

        # Identify previous entries for diffing/mentions
        b_start, b_end = detect_backer_tags(readme)
        prev_backer_identities = extract_section_identities(readme, b_start, b_end)
        s_start_prev, s_end_prev = detect_sponsor_tags(readme)
        prev_sponsor_identities = extract_section_identities(readme, s_start_prev, s_end_prev)

        # Backers (individuals)
        backers = fetch_members("backers.json")
        backers_md = generate_markdown(backers, empty_message: "No backers yet. Be the first!", default_name: "Backer")
        updated = replace_between_tags(readme, b_start, b_end, backers_md)
        case updated
        when :not_found
          updated_readme = readme
          backers_changed = false
          new_backers = []
        when :no_change
          updated_readme = readme
          backers_changed = false
          new_backers = []
        else
          updated_readme = updated
          backers_changed = true
          new_backers = compute_new_members(prev_backer_identities, backers)
        end

        # Sponsors (organizations)
        sponsors = fetch_members("sponsors.json")
        sponsors_md = generate_markdown(sponsors, empty_message: "No sponsors yet. Be the first!", default_name: "Sponsor")
        s_start, s_end = detect_sponsor_tags(updated_readme)
        updated2 = replace_between_tags(updated_readme, s_start, s_end, sponsors_md)
        case updated2
        when :not_found
          sponsors_changed = false
          final = updated_readme
          new_sponsors = []
        when :no_change
          sponsors_changed = false
          final = updated_readme
          new_sponsors = []
        else
          sponsors_changed = true
          final = updated2
          new_sponsors = compute_new_members(prev_sponsor_identities, sponsors)
        end

        if !backers_changed && !sponsors_changed
          if b_start == :not_found && s_start == :not_found
            ts = tag_strings
            warn("No recognized Open Collective tags found in #{@readme_path}. Expected one or more of: " \
              "#{ts[:generic_start]}/#{ts[:generic_end]}, #{ts[:individuals_start]}/#{ts[:individuals_end]}, #{ts[:orgs_start]}/#{ts[:orgs_end]}.")
            # Do not exit the process during tests or library use; just return.
            return
          end
          puts "No changes to backers or sponsors sections in #{@readme_path}."
          return
        end

        File.write(@readme_path, final)
        msgs = []
        msgs << "backers" if backers_changed
        msgs << "sponsors" if sponsors_changed
        puts "Updated #{msgs.join(" and ")} section#{{true => "s", false => ""}[msgs.size > 1]} in #{@readme_path}."

        # Compose and perform commit with mentions if in a git repo
        perform_git_commit(new_backers, new_sponsors) if git_repo? && (backers_changed || sponsors_changed)
      end

      private

      def readme_osc_tag
        env = ENV["KETTLE_DEV_BACKER_README_OSC_TAG"].to_s
        return env unless env.strip.empty?
        if File.file?(OC_YML_PATH)
          begin
            yml = YAML.safe_load(File.read(OC_YML_PATH))
            if yml.is_a?(Hash)
              from_yml = yml["readme-osc-tag"] || yml[:"readme-osc-tag"]
              from_yml = from_yml.to_s if from_yml
              return from_yml unless from_yml.nil? || from_yml.strip.empty?
            end
          rescue StandardError
          end
        end
        README_OSC_TAG_DEFAULT
      end

      def tag_strings
        base = readme_osc_tag
        {
          generic_start: "<!-- #{base}:START -->",
          generic_end: "<!-- #{base}:END -->",
          individuals_start: "<!-- #{base}-INDIVIDUALS:START -->",
          individuals_end: "<!-- #{base}-INDIVIDUALS:END -->",
          orgs_start: "<!-- #{base}-ORGANIZATIONS:START -->",
          orgs_end: "<!-- #{base}-ORGANIZATIONS:END -->",
        }
      end

      def resolve_handle
        env = ENV["OPENCOLLECTIVE_HANDLE"]
        return env unless env.nil? || env.strip.empty?
        if File.file?(OC_YML_PATH)
          yml = YAML.safe_load(File.read(OC_YML_PATH))
          handle = yml.is_a?(Hash) ? yml["collective"] || yml[:collective] : nil
          return handle.to_s unless handle.nil? || handle.to_s.strip.empty?
        end
        abort("ERROR: Open Collective handle not provided. Set OPENCOLLECTIVE_HANDLE or add 'collective: <handle>' to .opencollective.yml.")
      end

      def fetch_members(path)
        url = URI("https://opencollective.com/#{@handle}/#{path}")
        response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == "https") do |conn|
          conn.read_timeout = 10
          conn.open_timeout = 5
          req = Net::HTTP::Get.new(url)
          req["User-Agent"] = "kettle-dev/README-backers"
          conn.request(req)
        end
        return [] unless response.is_a?(Net::HTTPSuccess)
        parsed = JSON.parse(response.body)
        Array(parsed).map do |h|
          Backer.new(
            name: h["name"],
            image: (h["image"].to_s.strip.empty? ? nil : h["image"]),
            website: (h["website"].to_s.strip.empty? ? nil : h["website"]),
            profile: (h["profile"].to_s.strip.empty? ? nil : h["profile"]),
          )
        end
      rescue JSON::ParserError => e
        warn("Error parsing #{path} JSON: #{e.message}")
        []
      rescue StandardError => e
        warn("Error fetching #{path}: #{e.class}: #{e.message}")
        []
      end

      def generate_markdown(members, empty_message:, default_name:)
        return empty_message if members.nil? || members.empty?
        members.map do |m|
          image_url = m.image || DEFAULT_AVATAR
          link = m.website || m.profile || "#"
          name = (m.name && !m.name.strip.empty?) ? m.name : default_name
          "[![#{escape_text(name)}](#{image_url})](#{link})"
        end.join(" ")
      end

      def replace_between_tags(content, start_tag, end_tag, new_content)
        return :not_found if start_tag == :not_found || end_tag == :not_found
        start_index = content.index(start_tag)
        end_index = content.index(end_tag)
        return :not_found if start_index.nil? || end_index.nil? || end_index < start_index
        before = content[0..start_index + start_tag.length - 1]
        after = content[end_index..-1]
        replacement = "#{start_tag}\n#{new_content}\n#{end_tag}"
        current_block = content[start_index..end_index + end_tag.length - 1]
        return :no_change if current_block == replacement
        trailing = after[end_tag.length..-1] || ""
        "#{before}\n#{new_content}\n#{end_tag}#{trailing}"
      end

      def detect_backer_tags(content)
        ts = tag_strings
        if content.include?(ts[:generic_start]) && content.include?(ts[:generic_end])
          [ts[:generic_start], ts[:generic_end]]
        elsif content.include?(ts[:individuals_start]) && content.include?(ts[:individuals_end])
          [ts[:individuals_start], ts[:individuals_end]]
        else
          [:not_found, :not_found]
        end
      end

      def detect_sponsor_tags(content)
        ts = tag_strings
        if content.include?(ts[:orgs_start]) && content.include?(ts[:orgs_end])
          [ts[:orgs_start], ts[:orgs_end]]
        else
          [:not_found, :not_found]
        end
      end

      def extract_section_identities(content, start_tag, end_tag)
        return Set.new unless start_tag && end_tag && start_tag != :not_found && end_tag != :not_found
        start_index = content.index(start_tag)
        end_index = content.index(end_tag)
        return Set.new if start_index.nil? || end_index.nil? || end_index < start_index
        block = content[(start_index + start_tag.length)...end_index]
        identities = Set.new
        block.to_s.scan(/\[!\[[^\]]*\]\([^\)]*\)\]\(([^\)]+)\)/) do |m|
          href = (m[0] || "").strip
          identities << href.downcase unless href.empty?
        end
        block.to_s.scan(/\[!\[([^\]]*)\]\([^\)]*\)\]\([^\)]*\)/) do |m|
          alt = (m[0] || "").strip
          identities << alt.downcase unless alt.empty?
        end
        identities
      end

      def compute_new_members(previous_identities, members)
        prev = previous_identities || Set.new
        members.select do |m|
          id = identity_for_member(m)
          !prev.include?(id)
        end
      end

      def identity_for_member(m)
        if m.profile && !m.profile.strip.empty?
          m.profile.strip.downcase
        elsif m.website && !m.website.strip.empty?
          m.website.strip.downcase
        elsif m.name && !m.name.strip.empty?
          m.name.strip.downcase
        else
          ""
        end
      end

      def mention_for_member(m, default_name: "Member")
        handle = github_handle_from_urls(m.profile, m.website)
        return "@#{handle}" if handle
        name = (m.name && !m.name.strip.empty?) ? m.name.strip : default_name
        name
      end

      def github_handle_from_urls(*urls)
        urls.compact.each do |u|
          begin
            uri = URI.parse(u)
          rescue URI::InvalidURIError
            next
          end
          next unless uri&.host&.downcase&.end_with?("github.com")
          path = (uri.path || "").sub(%r{^/}, "").sub(%r{/$}, "")
          next if path.empty?
          parts = path.split("/")
          candidate = if parts[0].downcase == "sponsors" && parts[1]
            parts[1]
          else
            parts[0]
          end
          candidate = candidate.gsub(%r{[^a-zA-Z0-9-]}, "")
          return candidate unless candidate.empty?
        end
        nil
      end

      def perform_git_commit(new_backers, new_sponsors)
        backer_mentions = new_backers.map { |m| mention_for_member(m, default_name: "Backer") }.uniq
        sponsor_mentions = new_sponsors.map { |m| mention_for_member(m, default_name: "Subscriber") }.uniq
        title = commit_subject
        lines = [title]
        lines << ""
        lines << "Backers: #{backer_mentions.join(", ")}" unless backer_mentions.empty?
        lines << "Subscribers: #{sponsor_mentions.join(", ")}" unless sponsor_mentions.empty?
        message = lines.join("\n")
        system("git", "add", @readme_path)
        if system("git", "diff", "--cached", "--quiet")
          return
        end
        system("git", "commit", "-m", message)
      end

      def commit_subject
        env = ENV["KETTLE_README_BACKERS_COMMIT_SUBJECT"].to_s
        return env unless env.strip.empty?
        if File.file?(OC_YML_PATH)
          begin
            yml = YAML.safe_load(File.read(OC_YML_PATH))
            if yml.is_a?(Hash)
              from_yml = yml["readme-backers-commit-subject"] || yml[:"readme-backers-commit-subject"]
              from_yml = from_yml.to_s if from_yml
              return from_yml unless from_yml.nil? || from_yml.strip.empty?
            end
          rescue StandardError
          end
        end
        COMMIT_SUBJECT_DEFAULT
      end

      def git_repo?
        system("git", "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
      end

      def escape_text(text)
        text.gsub("[", "\\[").gsub("]", "\\]")
      end
    end
  end
end
