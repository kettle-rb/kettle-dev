# frozen_string_literal: true

RSpec.describe Kettle::EmojiRegex do
  describe "::REGEX" do
    let(:regex) { described_class::REGEX }

    it "matches a simple emoji character" do
      # Grinning Face U+1F600
      emoji = "😀"
      expect(emoji).to match(regex)
    end

    it "can be used to extract full cluster for emoji with variation selector (⏳️) at H1 start" do
      header = "# ⏳️ Rspec::PendingFor"
      after = header.sub(/^#\s+/, "")
      emojis = +""
      while after =~ /\A#{regex.source}/u
        cluster = after[/\A\X/u]
        emojis << cluster
        after = after[cluster.length..-1].to_s
      end
      expect(emojis).to eq("⏳️")
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
