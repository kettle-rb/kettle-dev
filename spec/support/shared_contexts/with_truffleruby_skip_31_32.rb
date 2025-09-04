# frozen_string_literal: true

# Shared context to skip examples on TruffleRuby versions that map to Ruby 3.1..3.2
# TruffleRuby v23.0 and v23.1 correspond to Ruby 3.1 and 3.2 compatibility levels.
# These specs are incompatible on those engines/versions, so we skip them.
RSpec.shared_context "with truffleruby 3.1..3.2 skip" do
  before do
    skip_for(
      reason: "Incompatible with TruffleRuby v23.0–23.1 (Ruby 3.1–3.2)",
      engine: "truffleruby",
      versions: %w[3.1 3.2],
    )
  end
end
