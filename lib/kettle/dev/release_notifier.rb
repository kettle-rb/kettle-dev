# frozen_string_literal: true

module Kettle
  module Dev
    module ReleaseNotifier
      class << self
        def alert(message, stream: $stderr)
          return unless enabled?

          stream.write("\a") if terminal_bell?
          stream.puts(message)
          stream.flush if stream.respond_to?(:flush)
        end

        private

        def enabled?
          !ENV.fetch("KETTLE_RELEASE_SECRET_ALERT", "true").match?(/\A(?:false|0|no|off|disabled)\z/i)
        end

        def terminal_bell?
          !ENV.fetch("KETTLE_RELEASE_SECRET_BELL", "true").match?(/\A(?:false|0|no|off|disabled)\z/i)
        end
      end
    end
  end
end
