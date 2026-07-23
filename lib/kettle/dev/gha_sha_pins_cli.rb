# frozen_string_literal: true

module Kettle
  module Dev
    begin
      require "kettle/gha/pins/cli"
      GhaShaPinsCLI = Kettle::Gha::Pins::CLI
    rescue LoadError
      # Compatibility wrapper for Ruby versions where kettle-gha-pins is not
      # installable. The standalone gem currently requires Ruby >= 3.2.
      class GhaShaPinsCLI
        def initialize(*)
        end

        def run!
          warn("kettle-gha-pins is not available; install Ruby >= 3.2 and the kettle-gha-pins gem to validate GitHub Actions SHA pins.")
          1
        end
      end
    end
  end
end
