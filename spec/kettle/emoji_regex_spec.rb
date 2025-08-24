# frozen_string_literal: true

require "kettle/emoji_regex"

RSpec.describe Kettle::EmojiRegex do
  describe "::REGEX" do
    let(:regex) { described_class::REGEX }

    it "matches a simple emoji character" do
      # Grinning Face U+1F600
      emoji = "😀"
      expect(emoji).to match(regex)
    end

    it "does not match a plain ASCII letter" do
      char = "A"
      expect(char).not_to match(regex)
    end

    it "does not match a plain hash sign without emoji modifiers" do
      char = "#"
      expect(char).not_to match(regex)
    end
  end
end
