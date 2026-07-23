# frozen_string_literal: true

module Kettle
  module Dev
    begin
      require "kettle/gha/pins/cli"
      GhaShaPinsCLI = Kettle::Gha::Pins::CLI
    rescue LoadError
      # Compatibility wrapper for unusual installs that omit the runtime dependency.
      class GhaShaPinsCLI
        def initialize(*)
        end

        def run!
          warn("kettle-gha-pins is not available; install the kettle-gha-pins gem to validate GitHub Actions SHA pins.")
          1
        end
      end
    end
  end
end
