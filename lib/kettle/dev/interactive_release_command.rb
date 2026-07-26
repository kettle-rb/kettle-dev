# frozen_string_literal: true

require "open3"

module Kettle
  module Dev
    class InteractiveReleaseCommand
      def initialize(secrets_provider:, input: $stdin, output: $stdout, error: $stderr)
        @secrets_provider = secrets_provider
        @input = input
        @output = output
        @error = error
        @gem_signing_passphrase = nil
      end

      def call(env, cmd)
        return call_with_pty(env, cmd) if pty_available?

        call_with_open3(env, cmd)
      end

      private

      attr_reader :secrets_provider

      def call_with_pty(env, cmd)
        stdout_str = +""
        status = nil
        PTY.spawn(env, cmd) do |output, input, pid|
          begin
            loop do
              chunk = output.readpartial(1024)
              stdout_str << chunk
              @output.print(chunk)
              handle_prompt(input, chunk)
            end
          rescue Errno::EIO
            # PTY raises EIO when the child process exits after closing the slave.
          rescue Kettle::Dev::Error
            Process.kill("TERM", pid)
            raise
          ensure
            _, status = Process.wait2(pid)
          end
        end
        [stdout_str, "", status]
      end

      def call_with_open3(env, cmd)
        stdout_str = +""
        stderr_str = +""
        status = nil
        Open3.popen3(env, cmd) do |input, output, error, wait_thread|
          readers = [output, error]
          until readers.empty?
            ready = IO.select(readers)
            ready.first.each do |reader|
              begin
                chunk = reader.readpartial(1024)
                if reader.equal?(output)
                  stdout_str << chunk
                  @output.print(chunk)
                else
                  stderr_str << chunk
                  @error.print(chunk)
                end
                handle_prompt(input, chunk)
              rescue EOFError
                readers.delete(reader)
              end
            end
          end
          status = wait_thread.value
        end
        [stdout_str, stderr_str, status]
      end

      def handle_prompt(input, chunk)
        if otp_prompt?(chunk)
          write_secret(input, secrets_provider.rubygems_otp, label: "RubyGems MFA code") if otp_response_prompt?(chunk)
          return
        end

        write_secret(input, gem_signing_passphrase, label: "gem signing passphrase") if signing_password_prompt?(chunk)
      end

      def gem_signing_passphrase
        @gem_signing_passphrase ||= secrets_provider.gem_signing_passphrase.to_s
      end

      def write_secret(input, value, label:)
        secret = value.to_s
        if secret.empty?
          raise Kettle::Dev::Error, "#{label} prompt reached, but the configured release secrets provider returned no value. Aborting because secret prompts are not allowed when a secrets provider is configured."
        end

        @output.puts("#{label} loaded from configured secrets provider.")
        input.write("#{secret}\n")
        input.flush
      end

      def otp_prompt?(chunk)
        chunk.match?(/(?:multi-factor authentication|OTP code|one-time password|\bCode:\s*)/i)
      end

      def otp_response_prompt?(chunk)
        chunk.match?(/(?:OTP code|one-time password|\bCode:\s*)/i)
      end

      def signing_password_prompt?(chunk)
        chunk.match?(/(?:enter\s+)?(?:PEM\s+)?pass(?:\s|-)?phrase\s*(?:for\s+[^:]+)?[:?]\s*\z/i) ||
          chunk.match?(/(?:PEM|private key) password\s*[:?]\s*\z/i)
      end

      def pty_available?
        return false unless RUBY_ENGINE == "ruby"

        require "pty"
        true
      rescue LoadError
        false
      end
    end
  end
end
