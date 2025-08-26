# frozen_string_literal: true

module Kettle
  module Dev
    # Exit/abort indirection layer to allow controllable behavior in tests.
    #
    # Production/default behavior delegates to Kernel.abort / Kernel.exit,
    # which raise SystemExit. Specs can stub these methods to avoid terminating
    # the process or to assert on arguments without coupling to Kernel.
    #
    # Example (RSpec):
    #   allow(Kettle::Dev::ExitAdapter).to receive(:abort).and_raise(SystemExit.new(1))
    #
    # This adapter mirrors the "mockable adapter" approach used for GitAdapter.
    module ExitAdapter
      module_function

      # Abort the current execution with a message. By default this calls Kernel.abort,
      # which raises SystemExit after printing the message to STDERR.
      #
      # @param msg [String]
      # @return [void]
      def abort(msg)
        Kernel.abort(msg)
      end

      # Exit the current process with a given status code. By default this calls Kernel.exit.
      #
      # @param status [Integer]
      # @return [void]
      def exit(status = 0)
        Kernel.exit(status)
      end
    end
  end
end
