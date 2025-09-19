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
      private

      def abort(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      end

      public

      # Default README is the one in the current working directory of the host project
      README_PATH = File.expand_path("README.md", Dir.pwd)
      README_OSC_TAG_DEFAULT = "OPENCOLLECTIVE"
      COMMIT_SUBJECT_DEFAULT = "💸 Thanks 🙏 to our new backers 🎒 and subscribers 📜"
      # Deprecated constant maintained for backwards compatibility in tests/specs.
      # Prefer OpenCollectiveConfig.yaml_path going forward, but resolve to the host project root.
      OC_YML_PATH = OpenCollectiveConfig.yaml_path(Dir.pwd)

      private

      # Emit a debug log line when kettle-dev debugging is enabled.
      # Controlled by KETTLE_DEV_DEBUG=true (or DEBUG=true as fallback).
      # @param msg [String]
      # @return [void]
      def debug_log(msg)
        return unless Kettle::Dev::DEBUGGING
        Kernel.warn("[readme_backers] #{msg}")
      rescue StandardError
        # never raise from a standard error within debug logging
      end

      public

      # Ruby 2.3 compatibility: Struct keyword_init added in Ruby 2.5
      # Switch to struct when dropping ruby < 2.5
      # Backer = Struct.new(:name, :image, :website, :profile, keyword_init: true)
      # Fallback for Ruby < 2.5 where Struct keyword_init is unsupported
      class Backer
        ROLE = "BACKER"
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

      # Validate environment preconditions for running the updater.
      # Ensures README_UPDATER_TOKEN is present. If missing, prints guidance and raises.
      #
      # @return [void]
      # @raise [RuntimeError] when README_UPDATER_TOKEN is not provided
      def validate
        token = ENV["README_UPDATER_TOKEN"].to_s
        if token.strip.empty?
          repo = ENV["REPO"] || ENV["GITHUB_REPOSITORY"]
          org = repo&.to_s&.split("/")&.first
          org_url = if org && !org.strip.empty?
            "https://github.com/organizations/#{org}/settings/secrets/actions"
          else
            "https://github.com/organizations/YOUR_ORG/settings/secrets/actions"
          end
          $stderr.puts "ERROR: README_UPDATER_TOKEN is not set."
          $stderr.puts "Please create an organization-level Actions secret named README_UPDATER_TOKEN at:"
          $stderr.puts "  #{org_url}"
          $stderr.puts "Then update the workflow to reference it, or provide README_UPDATER_TOKEN in the environment."
          raise 'Missing ENV["README_UPDATER_TOKEN"]'
        end
        nil
      end

      def run!
        validate
        debug_log("Starting run: handle=#{@handle.inspect}, readme=#{@readme_path}")
        debug_log("Resolved OSC tag base=#{readme_osc_tag.inspect}")
        readme = File.read(@readme_path)

        # Identify previous entries for diffing/mentions
        b_start, b_end = detect_backer_tags(readme)
        s_start_prev, s_end_prev = detect_sponsor_tags(readme)
        debug_log("Backer tags present=#{b_start != :not_found && b_end != :not_found}; Sponsor tags present=#{s_start_prev != :not_found && s_end_prev != :not_found}")
        prev_backer_identities = extract_section_identities(readme, b_start, b_end)
        prev_sponsor_identities = extract_section_identities(readme, s_start_prev, s_end_prev)

        # Fetch all BACKER-role members once and partition by tier
        debug_log("Fetching OpenCollective members JSON for handle=#{@handle} ...")
        raw = fetch_all_backers_raw
        debug_log("Fetched #{Array(raw).size} members (role=#{Backer::ROLE}) before tier partitioning")
        if Kettle::Dev::DEBUGGING
          tier_counts = Array(raw).group_by { |h| (h["tier"] || "").to_s.strip }.transform_values(&:size)
          debug_log("Tier distribution: #{tier_counts}")
          empty_tier = Array(raw).select { |h| h["tier"].to_s.strip.empty? }
          unless empty_tier.empty?
            debug_log("Members with empty tier: count=#{empty_tier.size}; showing up to 5 samples:")
            empty_tier.first(5).each_with_index do |m, i|
              debug_log("  [empty-tier ##{i + 1}] name=#{m["name"].inspect}, isActive=#{m["isActive"].inspect}, profile=#{m["profile"].inspect}, website=#{m["website"].inspect}")
            end
          end
          other_tiers = Array(raw).map { |h| h["tier"].to_s.strip }.reject { |t| t.empty? || t.casecmp("Backer").zero? || t.casecmp("Sponsor").zero? }
          unless other_tiers.empty?
            counts = other_tiers.group_by { |t| t }.transform_values(&:size)
            debug_log("Non-standard tiers present (excluding Backer/Sponsor): #{counts}")
          end
        end
        backers_hashes = Array(raw).select { |h| h["tier"].to_s.strip.casecmp("Backer").zero? }
        sponsors_hashes = Array(raw).select { |h| h["tier"].to_s.strip.casecmp("Sponsor").zero? }

        backers = map_hashes_to_backers(backers_hashes)
        sponsors = map_hashes_to_backers(sponsors_hashes)
        debug_log("Partitioned counts => Backers=#{backers.size}, Sponsors=#{sponsors.size}")
        if Kettle::Dev::DEBUGGING && backers.empty? && sponsors.empty? && Array(raw).any?
          debug_log("No Backer or Sponsor tiers matched among #{Array(raw).size} BACKER-role records. If tiers are empty, they will not appear in Backers/Sponsors sections.")
        end

        # Additional dynamic tiers (exclude Backer/Sponsor)
        extra_map = {}
        Array(raw).group_by { |h| h["tier"].to_s.strip }.each do |tier, members|
          normalized = tier.empty? ? "Donors" : tier
          next if normalized.casecmp("Backer").zero? || normalized.casecmp("Sponsor").zero?
          extra_map[normalized] = map_hashes_to_backers(members)
        end
        debug_log("Extra tiers detected: #{extra_map.keys.sort}") unless extra_map.empty?

        backers_md = generate_markdown(backers, empty_message: "No backers yet. Be the first!", default_name: "Backer")
        sponsors_md_base = generate_markdown(sponsors, empty_message: "No sponsors yet. Be the first!", default_name: "Sponsor")

        extra_tiers_md = generate_extra_tiers_markdown(extra_map)
        sponsors_md = if extra_tiers_md.empty?
          sponsors_md_base
        else
          [sponsors_md_base, "", extra_tiers_md].join("\n")
        end

        # Update backers section
        updated = replace_between_tags(readme, b_start, b_end, backers_md)
        case updated
        when :not_found
          debug_log("Backers tag block not found; skipping backers section update")
          updated_readme = readme
          backers_changed = false
          new_backers = []
        when :no_change
          debug_log("Backers section unchanged (generated markdown matches existing block)")
          updated_readme = readme
          backers_changed = false
          new_backers = []
        else
          updated_readme = updated
          backers_changed = true
          new_backers = compute_new_members(prev_backer_identities, backers)
          debug_log("Backers section updated; new_backers=#{new_backers.size}")
        end

        # Update sponsors section (with extra tiers appended when present)
        s_start, s_end = detect_sponsor_tags(updated_readme)
        # If there is no sponsors section but there is a backers section, append extra tiers to backers instead.
        if s_start == :not_found && !extra_tiers_md.empty? && b_start != :not_found
          debug_log("Sponsors tags not found; appending extra tiers under Backers section")
          backers_md_with_extra = [backers_md, "", extra_tiers_md].join("\n")
          updated = replace_between_tags(updated_readme, b_start, b_end, backers_md_with_extra)
          updated_readme = updated unless updated == :no_change || updated == :not_found
        end

        updated2 = replace_between_tags(updated_readme, s_start, s_end, sponsors_md)
        case updated2
        when :not_found
          debug_log("Sponsors tag block not found; skipping sponsors section update")
          sponsors_changed = false
          final = updated_readme
          new_sponsors = []
        when :no_change
          debug_log("Sponsors section unchanged (generated markdown matches existing block)")
          sponsors_changed = false
          final = updated_readme
          new_sponsors = []
        else
          sponsors_changed = true
          final = updated2
          new_sponsors = compute_new_members(prev_sponsor_identities, sponsors)
          debug_log("Sponsors section updated; new_sponsors=#{new_sponsors.size}")
        end

        if !backers_changed && !sponsors_changed
          if b_start == :not_found && s_start == :not_found
            ts = tag_strings
            warn("No recognized Open Collective tags found in #{@readme_path}. Expected one or more of: " \
              "#{ts[:generic_start]}/#{ts[:generic_end]}, #{ts[:individuals_start]}/#{ts[:individuals_end]}, #{ts[:orgs_start]}/#{ts[:orgs_end]}.")
            debug_log("Missing tags: looked for #{ts}")
            # Do not exit the process during tests or library use; just return.
            return
          end
          debug_log("No changes detected after processing; Backers=#{backers.size}, Sponsors=#{sponsors.size}, ExtraTiers=#{extra_map.keys.size}")
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
          rescue StandardError => e
            Kettle::Dev.debug_error(e, __method__)
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
        OpenCollectiveConfig.handle(required: true, root: Dir.pwd)
      end

      def fetch_all_backers_raw
        api_path = "members/all.json"
        url = URI("https://opencollective.com/#{@handle}/#{api_path}")
        debug_log("GET #{url}")
        response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == "https") do |conn|
          conn.read_timeout = 10
          conn.open_timeout = 5
          req = Net::HTTP::Get.new(url)
          req["User-Agent"] = "kettle-dev/README-backers"
          conn.request(req)
        end
        unless response.is_a?(Net::HTTPSuccess)
          body_len = (response.respond_to?(:body) && response.body) ? response.body.bytesize : 0
          code = response.respond_to?(:code) ? response.code : response.class.name
          warn("OpenCollective API non-success for #{api_path}: status=#{code}, body_len=#{body_len}")
          debug_log("Response body (truncated 500 bytes): #{response.body.to_s[0, 500]}") if Kettle::Dev::DEBUGGING && body_len.to_i > 0
          return []
        end

        parsed = JSON.parse(response.body)
        all = Array(parsed)
        filtered = all.select { |h| h["role"].to_s.upcase == Backer::ROLE }
        debug_log("Parsed #{all.size} records; filtered BACKER => #{filtered.size}")
        filtered
      rescue JSON::ParserError => e
        warn("Error parsing #{api_path} JSON: #{e.message}")
        debug_log("Body that failed to parse (truncated 500): #{response&.body.to_s[0, 500]}")
        []
      rescue StandardError => e
        warn("Error fetching #{api_path}: #{e.class}: #{e.message}")
        debug_log(e.backtrace.join("\n"))
        []
      end

      def map_hashes_to_backers(hashes)
        Array(hashes).map do |h|
          Backer.new(
            name: h["name"],
            image: begin
              # Prefer OpenCollective's "avatar" key; fallback to legacy "image"
              img = h["avatar"]
              img = h["image"] if img.to_s.strip.empty?
              img.to_s.strip.empty? ? nil : img
            end,
            website: (h["website"].to_s.strip.empty? ? nil : h["website"]),
            profile: (h["profile"].to_s.strip.empty? ? nil : h["profile"]),
          )
        end
      end

      def generate_markdown(members, empty_message:, default_name:)
        return empty_message if members.nil? || members.empty?

        members.map do |m|
          # Treat empty strings as missing for image/link selection
          image_url = (m.image && !m.image.to_s.strip.empty?) ? m.image : nil
          primary_link = (m.website && !m.website.to_s.strip.empty?) ? m.website : nil
          fallback_link = (m.profile && !m.profile.to_s.strip.empty?) ? m.profile : nil
          link = primary_link || fallback_link || "#"
          name = (m.name && !m.name.strip.empty?) ? m.name : default_name
          if image_url
            "[![#{escape_text(name)}](#{image_url})](#{link})"
          else
            "[#{escape_text(name)}](#{link})"
          end
        end.join(" ")
      end

      # Build markdown for any additional tiers beyond Backer/Sponsor.
      # Accepts a Hash of { tier_name => [Backer, ...] }.
      # Returns an empty string when there are no extra tiers.
      def generate_extra_tiers_markdown(extra_map)
        return "" if extra_map.nil? || extra_map.empty?

        lines = []
        extra_map.keys.sort.each do |tier|
          members = extra_map[tier]
          next if members.nil? || members.empty?
          lines << "### Open Collective for #{tier}"
          lines << ""
          lines << generate_markdown(members, empty_message: "", default_name: tier)
          lines << ""
        end
        lines.join("\n")
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
        # 1) Image-style link wrappers: [![ALT](IMG)](HREF)
        block.to_s.scan(/\[!\[[^\]]*\]\([^\)]*\)\]\(([^\)]+)\)/) do |m|
          href = (m[0] || "").strip
          identities << href.downcase unless href.empty?
        end
        # 2) Capture ALT text from image-style wrappers for name identity
        block.to_s.scan(/\[!\[([^\]]*)\]\([^\)]*\)\]\([^\)]*\)/) do |m|
          alt = (m[0] || "").strip
          identities << alt.downcase unless alt.empty?
        end
        # 3) Plain markdown links: [TEXT](HREF)
        block.to_s.scan(/\[([^!][^\]]*)\]\(([^\)]+)\)/) do |m|
          text = (m[0] || "").strip
          href = (m[1] || "").strip
          identities << href.downcase unless href.empty?
          identities << text.downcase unless text.empty?
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
          rescue StandardError => e
            Kettle::Dev.debug_error(e, __method__)
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
