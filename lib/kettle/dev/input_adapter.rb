# frozen_string_literal: true

module Kettle
  module Dev
    # Input indirection layer to make interactive prompts safe in tests.
    #
    # Production/default behavior delegates to $stdin.gets (or Kernel#gets)
    # so application code does not read from STDIN directly. In specs, mock
    # this adapter's methods to return deterministic answers without touching
    # global IO.
    #
    # Example (RSpec):
    #   allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
    #
    # This mirrors the "mockable adapter" approach used for GitAdapter and ExitAdapter.
    module InputAdapter
      module_function

      # Read one line from the standard input, including the trailing newline if
      # present. Returns nil on EOF, consistent with IO#gets.
      #
      # @param args [Array] any args are forwarded to $stdin.gets for compatibility
      # @return [String, nil]
      def gets(*args)
        $stdin.gets(*args)
      end

      def tty?
        $stdin.tty?
      end

      # Read one line from standard input, raising EOFError on end-of-file.
      # Provided for convenience symmetry with IO#readline when needed.
      #
      # @param args [Array]
      # @return [String]
      def readline(*args)
        line = gets(*args)
        raise EOFError, "end of file reached" if line.nil?

        line
      end
    end
  end
end
