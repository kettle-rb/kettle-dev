# Legacy helper used by some specs; no longer globally assigned to $stdin.
# Specs that set $stdin = KettleTestInputMachine.new(default: ...) will be
# respected by the mocked input adapter context for defaults.
class KettleTestInputMachine
  def initialize(default: nil)
    @default = default
  end

  def gets(*_args)
    (@default.nil? ? "\n" : @default.to_s) + ("\n" unless @default&.to_s&.end_with?("\n")).to_s
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
