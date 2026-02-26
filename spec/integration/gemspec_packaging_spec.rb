# frozen_string_literal: true

require "rubygems"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "kettle-dev gem packaging (example files exclusion)" do
  it "does not include any *.example files in the packaged gem (moved to kettle-jem)" do
    # Determine repo root using the public constant
    root = Kettle::Dev::GEM_ROOT

    # Load the gemspec without changing directories
    path = File.join(root, "kettle-dev.gemspec")
    spec = Gem::Specification.load(path)
    expect(spec).not_to be_nil

    packaged = spec.files.map { |p| p.sub(/\A\.\//, "") }.sort

    # No .example files should be packaged — they have been moved to kettle-jem
    example_files = packaged.select { |p| p.end_with?(".example") }
    expect(example_files).to eq([]), "Unexpected .example files in packaged gem: \n#{example_files.join("\n")}"
  end
end
# rubocop:enable RSpec/DescribeClass
