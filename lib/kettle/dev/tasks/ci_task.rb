# frozen_string_literal: true

# External
require "open3"
require "net/http"
require "json"
require "uri"
require "io/console"

module Kettle
  module Dev
    module Tasks
      module CITask
        module_function

        # Local abort indirection to enable mocking via ExitAdapter
        def abort(msg)
          Kettle::Dev::ExitAdapter.abort(msg)
        end
        module_function :abort

        # Runs `act` for a selected workflow. Option can be a short code or workflow basename.
        # @param opt [String, nil]
        def act(opt = nil)
          choice = opt&.strip

          root_dir = Kettle::Dev::CIHelpers.project_root
          workflows_dir = File.join(root_dir, ".github", "workflows")

          # Build mapping dynamically from workflow files; short code = first three letters of filename stem
          mapping = {}

          existing_files = if Dir.exist?(workflows_dir)
            Dir[File.join(workflows_dir, "*.yml")] + Dir[File.join(workflows_dir, "*.yaml")]
          else
            []
          end
          existing_basenames = existing_files.map { |p| File.basename(p) }

          exclusions = Kettle::Dev::CIHelpers.exclusions
          candidate_files = existing_basenames.uniq - exclusions
          candidate_files.sort.each do |fname|
            stem = fname.sub(/\.(ya?ml)\z/, "")
            code = stem[0, 3].to_s.downcase
            next if code.empty?
            mapping[code] ||= fname
          end

          dynamic_files = candidate_files - mapping.values
          display_code_for = {}
          mapping.keys.each { |k| display_code_for[k] = k }
          dynamic_files.each { |f| display_code_for[f] = "" }

          status_emoji = proc do |status, conclusion|
            case status
            when "queued" then "⏳️"
            when "in_progress" then "👟"
            when "completed" then ((conclusion == "success") ? "✅" : "🍅")
            else "⏳️"
            end
          end

          fetch_and_print_status = proc do |workflow_file|
            branch = Kettle::Dev::CIHelpers.current_branch
            org_repo = Kettle::Dev::CIHelpers.repo_info
            unless branch && org_repo
              puts "GHA status: (skipped; missing git branch or remote)"
              next
            end
            owner, repo = org_repo
            uri = URI("https://api.github.com/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/runs?branch=#{URI.encode_www_form_component(branch)}&per_page=1")
            req = Net::HTTP::Get.new(uri)
            req["User-Agent"] = "ci:act rake task"
            token = Kettle::Dev::CIHelpers.default_token
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

          run_act_for = proc do |file_path|
            ok = system("act", "-W", file_path)
            abort("ci:act failed: 'act' command not found or exited with failure") unless ok
          end

          if choice && !choice.empty?
            file = if mapping.key?(choice)
              mapping.fetch(choice)
            elsif !!(/\.(yml|yaml)\z/ =~ choice)
              choice
            else
              cand_yml = File.join(workflows_dir, "#{choice}.yml")
              cand_yaml = File.join(workflows_dir, "#{choice}.yaml")
              if File.file?(cand_yml)
                "#{choice}.yml"
              elsif File.file?(cand_yaml)
                "#{choice}.yaml"
              else
                "#{choice}.yml"
              end
            end
            file_path = File.join(workflows_dir, file)
            unless File.file?(file_path)
              puts "Unknown option or missing workflow file: #{choice} -> #{file}"
              puts "Available options:"
              mapping.each { |k, v| puts "  #{k.ljust(3)} => #{v}" }
              unless dynamic_files.empty?
                puts "  (others) =>"
                dynamic_files.each { |v| puts "        #{v}" }
              end
              abort("ci:act aborted")
            end
            fetch_and_print_status.call(file)
            run_act_for.call(file_path)
            return
          end

          # Interactive menu
          require "thread"
          tty = $stdout.tty?
          options = mapping.to_a + dynamic_files.map { |f| [f, f] }
          quit_code = "q"
          options_with_quit = options + [[quit_code, "(quit)"]]
          idx_by_code = {}
          options_with_quit.each_with_index { |(k, _v), i| idx_by_code[k] = i }

          branch = Kettle::Dev::CIHelpers.current_branch
          org = Kettle::Dev::CIHelpers.repo_info
          owner, repo = org if org
          token = Kettle::Dev::CIHelpers.default_token

          upstream = begin
            out, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
            status.success? ? out.strip : nil
          rescue StandardError
            nil
          end
          sha = begin
            out, status = Open3.capture2("git", "rev-parse", "--short", "HEAD")
            status.success? ? out.strip : nil
          rescue StandardError
            nil
          end
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

          placeholder = "[…]"
          options_with_quit.each_with_index do |(k, v), idx|
            status_col = (k == quit_code) ? "" : placeholder
            disp = (k == quit_code) ? k : display_code_for[k]
            line = format("%2d) %-3s => %-20s %s", idx + 1, disp, v, status_col)
            puts line
          end

          puts "(Fetching latest GHA status for branch #{branch || "n/a"} — you can type your choice and press Enter)"
          prompt = "Enter number or code (or 'q' to quit): "
          print(prompt)
          $stdout.flush

          # We need to sleep a bit here to ensure the terminal is ready for both
          #   input and writing status updates to each workflow's line
          sleep(0.2) unless Kettle::Dev::IS_CI

          selected = nil
          input_thread = Thread.new do
            begin
              selected = Kettle::Dev::InputAdapter.gets&.strip
            rescue Exception => error
              # Catch all exceptions in background thread, including SystemExit
              # NOTE: look into refactoring to minimize potential SystemExit.
              puts "Error in background thread: #{error.class}: #{error.message}" if Kettle::Dev::DEBUGGING
              selected = nil
            end
          end

          status_q = Queue.new
          workers = []
          start_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          options.each do |code, file|
            workers << Thread.new(code, file, owner, repo, branch, token, start_at) do |c, f, ow, rp, br, tk, st_at|
              begin
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
                  rescue Exception
                    # Catch all exceptions to prevent crashing the process from a worker thread
                    status_q << [c, f, "err"]
                  end
                  sleep(poll_interval)
                end
              rescue Exception
                # :nocov:
                # Catch all exceptions in the worker thread boundary, including SystemExit
                status_q << [c, f, "err"]
                # :nocov:
              end
            end
          end

          statuses = Hash.new(placeholder)

          loop do
            if selected
              break
            end

            begin
              code, file_name, display = status_q.pop(true)
              statuses[code] = display

              if tty
                idx = idx_by_code[code]
                if idx.nil?
                  puts "status #{code}: #{display}"
                  print(prompt)
                else
                  move_up = options_with_quit.size - idx + 1
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
              sleep(0.05)
            end
          end

          begin
            workers.each { |t| t.kill if t&.alive? }
          rescue StandardError
          end
          begin
            input_thread.kill if input_thread&.alive?
          rescue StandardError
          end

          input = selected
          abort("ci:act aborted: no selection") if input.nil? || input.empty?

          chosen_file = nil
          if !!(/^\d+$/ =~ input)
            idx = input.to_i - 1
            if idx < 0 || idx >= options_with_quit.length
              abort("ci:act aborted: invalid selection #{input}")
            end
            code, val = options_with_quit[idx]
            if code == quit_code
              puts "ci:act: quit"
              return
            else
              chosen_file = val
            end
          else
            code = input
            if ["q", "quit", "exit"].include?(code.downcase)
              puts "ci:act: quit"
              return
            end
            chosen_file = mapping[code]
            abort("ci:act aborted: unknown code '#{code}'") unless chosen_file
          end

          file_path = File.join(workflows_dir, chosen_file)
          abort("ci:act aborted: workflow not found: #{file_path}") unless File.file?(file_path)
          fetch_and_print_status.call(chosen_file)
          run_act_for.call(file_path)
          Kettle::Dev::CIMonitor.monitor_gitlab!(restart_hint: "bundle exec rake ci:act")
        end
      end
    end
  end
end
