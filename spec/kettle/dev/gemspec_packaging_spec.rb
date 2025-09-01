# frozen_string_literal: true

RSpec.describe "gemspec packaging" do # rubocop:disable RSpec/DescribeClass
  it "includes .env.local.example in spec.files so template can copy it" do
    # Load the gemspec in-process to access the computed files list
    gemspec_path = File.expand_path("../../../kettle-dev.gemspec", __dir__)
    spec = eval(File.read(gemspec_path), binding, gemspec_path) # rubocop:disable Security/Eval
    expect(spec.files).to include(".env.local.example")
  end
end
