# --- CI helpers ---
namespace :ci do
  # rubocop:disable ThreadSafety/NewThread
  desc "Run 'act' with a selected workflow. Usage: rake ci:act[loc] (short code = first 3 letters of filename, e.g., 'loc' => locked_deps.yml), rake ci:act[locked_deps], rake ci:act[locked_deps.yml], or rake ci:act (then choose)"
  task :act, [:opt] do |_t, args|
    require "io/console"
    require "open3"
    require "net/http"
    require "json"
    require "uri"
    require "kettle/dev/ci_helpers"

    # Build mapping dynamically from workflow files; short code = first three letters of filename.
    # Collisions are resolved by first-come wins via ||= as requested.
    mapping = {}

    # Normalize provided option. Accept either short code or the exact yml/yaml filename
    choice = args[:opt]&.strip
    root_dir = Kettle::Dev::CIHelpers.project_root
    workflows_dir = File.join(root_dir, ".github", "workflows")

    # Determine actual workflow files present, and prepare dynamic additions excluding specified files.
    existing_files = if Dir.exist?(workflows_dir)
      Dir[File.join(workflows_dir, "*.yml")] + Dir[File.join(workflows_dir, "*.yaml")]
    else
      []
    end
    existing_basenames = existing_files.map { |p| File.basename(p) }

    # Build short-code mapping (first 3 chars of filename stem), excluding some maintenance workflows.
    exclusions = Kettle::Dev::CIHelpers.exclusions
    candidate_files = existing_basenames.uniq - exclusions
    candidate_files.sort.each do |fname|
      stem = fname.sub(/\.(ya?ml)\z/, "")
      code = stem[0, 3].to_s.downcase
      next if code.empty?
      mapping[code] ||= fname # first-come wins on collisions
    end

    # Any remaining candidates that didn't get a unique shortcode are treated as dynamic (number-only) options
    dynamic_files = candidate_files - mapping.values

    # For internal status tracking and rendering, we use a display_code_for hash.
    # For mapped (short-code) entries, display_code is the short code.
    # For dynamic entries, display_code is empty string, but we key statuses by a unique code = the filename.
    display_code_for = {}
    mapping.keys.each { |k| display_code_for[k] = k }
    dynamic_files.each { |f| display_code_for[f] = "" }

    # Helpers
    get_branch = proc do
      out, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
      status.success? ? out.strip : nil
    end

    get_origin = proc do
      out, status = Open3.capture2("git", "config", "--get", "remote.origin.url")
      next nil unless status.success?
      url = out.strip
      # Support ssh and https URLs
      if url =~ %r{git@github.com:(.+?)/(.+?)(\.git)?$}
        [$1, $2.sub(/\.git\z/, "")]
      elsif url =~ %r{https://github.com/(.+?)/(.+?)(\.git)?$}
        [$1, $2.sub(/\.git\z/, "")]
      end
    end

    get_sha = proc do
      out, status = Open3.capture2("git", "rev-parse", "--short", "HEAD")
      status.success? ? out.strip : nil
    end

    get_upstream = proc do
      out, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
      if status.success?
        out.strip
      else
        br = get_branch.call
        br ? "origin/#{br}" : nil
      end
    end

    status_emoji = proc do |status, conclusion|
      case status
      when "queued"
        "⏳️"
      when "in_progress"
        "👟"
      when "completed"
        (conclusion == "success") ? "✅" : "🍅"
      else
        "⏳️"
      end
    end

    fetch_and_print_status = proc do |workflow_file|
      branch = get_branch.call
      org_repo = get_origin.call
      unless branch && org_repo
        puts "GHA status: (skipped; missing git branch or remote)"
        next
      end
      owner, repo = org_repo
      uri = URI("https://api.github.com/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/runs?branch=#{URI.encode_www_form_component(branch)}&per_page=1")
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "ci:act rake task"
      token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
      req["Authorization"] = "token #{token}" if token && !token.empty?

      begin
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        if res.is_a?(Net::HTTPSuccess)
          data = JSON.parse(res.body)
          run = data["workflow_runs"]&.first
          if run
            status = run["status"]
            conclusion = run["conclusion"]
            emoji = status_emoji.call(status, conclusion)
            details = [status, conclusion].compact.join("/")
            puts "Latest GHA (#{branch}) for #{workflow_file}: #{emoji} (#{details})"
          else
            puts "Latest GHA (#{branch}) for #{workflow_file}: none"
          end
        else
          puts "GHA status: request failed (#{res.code})"
        end
      rescue StandardError => e
        puts "GHA status: error #{e.class}: #{e.message}"
      end
    end

    def run_act_for(file_path)
      # Prefer array form to avoid shell escaping issues
      ok = system("act", "-W", file_path)
      abort("ci:act failed: 'act' command not found or exited with failure") unless ok
    end

    def process_success_response(res, c, f, old = nil, current = nil)
      data = JSON.parse(res.body)
      run = data["workflow_runs"]&.first
      append = (old && current) ? " (update git remote: #{old} → #{current})" : ""
      if run
        st = run["status"]
        con = run["conclusion"]
        emoji = case st
        when "queued" then "⏳️"
        when "in_progress" then "👟"
        when "completed" then ((con == "success") ? "✅" : "🍅")
        else "⏳️"
        end
        details = [st, con].compact.join("/")
        [c, f, "#{emoji} (#{details})#{append}"]
      else
        [c, f, "none#{append}"]
      end
    end

    if choice && !choice.empty?
      # If user passed a filename directly (with or without extension), resolve it
      file = if mapping.key?(choice)
        mapping.fetch(choice)
      elsif !!(/\.(yml|yaml)\z/ =~ choice)
        # Accept either full basename (without ext) or basename with .yml/.yaml
        choice
      else
        cand_yml = File.join(workflows_dir, "#{choice}.yml")
        cand_yaml = File.join(workflows_dir, "#{choice}.yaml")
        if File.file?(cand_yml)
          "#{choice}.yml"
        elsif File.file?(cand_yaml)
          "#{choice}.yaml"
        else
          # Fall back to .yml for error messaging; will fail below
          "#{choice}.yml"
        end
      end
      file_path = File.join(workflows_dir, file)
      unless File.file?(file_path)
        puts "Unknown option or missing workflow file: #{choice} -> #{file}"
        puts "Available options:"
        mapping.each { |k, v| puts "  #{k.ljust(3)} => #{v}" }
        # Also display dynamically discovered files
        unless dynamic_files.empty?
          puts "  (others) =>"
          dynamic_files.each { |v| puts "        #{v}" }
        end
        abort("ci:act aborted")
      end
      fetch_and_print_status.call(file)
      run_act_for(file_path)
      next
    end

    # No option provided: interactive menu with live GHA statuses via Threads (no Ractors)
    require "thread"

    tty = $stdout.tty?
    # Build options: first the filtered short-code mapping, then dynamic files (no short codes)
    options = mapping.to_a + dynamic_files.map { |f| [f, f] }

    # Add a Quit choice
    quit_code = "q"
    options_with_quit = options + [[quit_code, "(quit)"]]

    idx_by_code = {}
    options_with_quit.each_with_index { |(k, _v), i| idx_by_code[k] = i }

    # Determine repo context once
    branch = get_branch.call
    org = get_origin.call
    owner, repo = org if org
    token = ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]

    # Header with remote branch and SHA
    upstream = get_upstream.call
    sha = get_sha.call
    if org && branch
      puts "Repo: #{owner}/#{repo}"
    elsif org
      puts "Repo: #{owner}/#{repo}"
    else
      puts "Repo: n/a"
    end
    puts "Upstream: #{upstream || "n/a"}"
    puts "HEAD: #{sha || "n/a"}"
    puts

    puts "Select a workflow to run with 'act':"

    # Render initial menu with placeholder statuses
    placeholder = "[…]"
    options_with_quit.each_with_index do |(k, v), idx|
      status_col = (k == quit_code) ? "" : placeholder
      disp = (k == quit_code) ? k : display_code_for[k]
      line = format("%2d) %-3s => %-20s %s", idx + 1, disp, v, status_col)
      puts line
    end

    puts "(Fetching latest GHA status for branch #{branch || "n/a"} — you can type your choice and press Enter)"
    prompt = "Enter number or code (or 'q' to quit): "
    print prompt
    $stdout.flush

    # Thread + Queue to read user input
    input_q = Queue.new
    input_thread = Thread.new do
      line = $stdin.gets&.strip
      input_q << line
    end

    # Worker threads to fetch statuses and stream updates as they complete
    status_q = Queue.new
    workers = []

    # Capture a monotonic start time to guard against early race with terminal rendering
    start_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    options.each do |code, file|
      workers << Thread.new(code, file, owner, repo, branch, token, start_at) do |c, f, ow, rp, br, tk, st_at|
        begin
          # small initial delay if threads finish too quickly, to let the menu/prompt finish rendering
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          delay = 0.12 - (now - st_at)
          sleep(delay) if delay && delay > 0

          if ow.nil? || rp.nil? || br.nil?
            status_q << [c, f, "n/a"]
            Thread.exit
          end
          uri = URI("https://api.github.com/repos/#{ow}/#{rp}/actions/workflows/#{f}/runs?branch=#{URI.encode_www_form_component(br)}&per_page=1")
          poll_interval = Integer(ENV["CI_ACT_POLL_INTERVAL"] || 5)
          loop do
            begin
              req = Net::HTTP::Get.new(uri)
              req["User-Agent"] = "ci:act rake task"
              req["Authorization"] = "token #{tk}" if tk && !tk.empty?
              res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
              if res.is_a?(Net::HTTPSuccess)
                data = JSON.parse(res.body)
                run = data["workflow_runs"]&.first
                if run
                  st = run["status"]
                  con = run["conclusion"]
                  emoji = case st
                  when "queued" then "⏳️"
                  when "in_progress" then "👟"
                  when "completed" then ((con == "success") ? "✅" : "🍅")
                  else "⏳️"
                  end
                  details = [st, con].compact.join("/")
                  status_q << [c, f, "#{emoji} (#{details})"]
                  break if st == "completed"
                else
                  status_q << [c, f, "none"]
                  break
                end
              else
                status_q << [c, f, "fail #{res.code}"]
              end
            rescue StandardError
              status_q << [c, f, "err"]
            end
            sleep(poll_interval)
          end
        rescue StandardError
          status_q << [c, f, "err"]
        end
      end
    end

    # Live update loop: either statuses arrive or the user submits input
    statuses = Hash.new(placeholder)
    selected = nil

    loop do
      # Check for user input first (non-blocking)
      unless input_q.empty?
        selected = begin
          input_q.pop(true)
        rescue
          nil
        end
        break if selected
      end

      # Drain any available status updates without blocking
      begin
        code, file_name, display = status_q.pop(true)
        statuses[code] = display

        if tty
          idx = idx_by_code[code]
          if idx.nil?
            puts "status #{code}: #{display}"
            print(prompt)
          else
            move_up = options_with_quit.size - idx + 1 # 1 for instruction line + remaining options above last
            $stdout.print("\e[#{move_up}A\r\e[2K")
            disp = (code == quit_code) ? code : display_code_for[code]
            $stdout.print(format("%2d) %-3s => %-20s %s\n", idx + 1, disp, file_name, display))
            $stdout.print("\e[#{move_up - 1}B\r")
            $stdout.print(prompt)
          end
          $stdout.flush
        else
          puts "status #{code}: #{display}"
        end
      rescue ThreadError
        # Queue empty: brief sleep to avoid busy wait
        sleep(0.05)
      end
    end

    # Cleanup: kill any still-running threads
    begin
      workers.each { |t| t.kill if t&.alive? }
    rescue StandardError
      # ignore
    end
    begin
      input_thread.kill if input_thread&.alive?
    rescue StandardError
      # ignore
    end

    input = selected
    abort("ci:act aborted: no selection") if input.nil? || input.empty?

    # Normalize selection
    chosen_file = nil
    if !!(/^\d+$/ =~ input)
      idx = input.to_i - 1
      if idx < 0 || idx >= options_with_quit.length
        abort("ci:act aborted: invalid selection #{input}")
      end
      code, val = options_with_quit[idx]
      if code == quit_code
        puts "ci:act: quit"
        next
      else
        chosen_file = val
      end
    else
      code = input
      if ["q", "quit", "exit"].include?(code.downcase)
        puts "ci:act: quit"
        next
      end
      chosen_file = mapping[code]
      abort("ci:act aborted: unknown code '#{code}'") unless chosen_file
    end

    file_path = File.join(workflows_dir, chosen_file)
    abort("ci:act aborted: workflow not found: #{file_path}") unless File.file?(file_path)

    # Print status for the chosen workflow (for consistency)
    fetch_and_print_status.call(chosen_file)
    run_act_for(file_path)
  end
  # rubocop:enable ThreadSafety/NewThread
end
