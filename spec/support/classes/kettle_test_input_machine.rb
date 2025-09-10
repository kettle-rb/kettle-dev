# Legacy helper used by some specs; no longer globally assigned to $stdin.
# Specs that set $stdin = KettleTestInputMachine.new(default: ...) will be
# respected by the mocked input adapter context for defaults.
class KettleTestInputMachine
  def initialize(default: nil)
    @default = default
  end

  def gets(*_args)
    base = @default.nil? ? "" : @default.to_s
    base.end_with?("\n") ? base : (base + "\n")
  end

  def readline(*_args)
    gets
  end

  def read(*_args)
    ""
  end

  def each_line
    return enum_for(:each_line) unless block_given?

    nil
  end

  def tty?
    false
  end
end
