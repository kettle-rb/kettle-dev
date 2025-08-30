# frozen_string_literal: true

require "rake"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("allowed" => "true")
  end

  it "carries over key fields from original gemspec when overwriting with example (after replacements)" do
    Dir.mktmpdir do |gem_root|
      Dir.mktmpdir do |project_root|
        # Template gemspec example with tokens and default summary/description starting with a grapheme
        File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "kettle-dev"
            spec.version = "1.0.0"
            spec.authors = ["Template Author"]
            spec.email = ["template@example.com"]
            spec.summary = "🍲 Template summary"
            spec.description = "🍲 Template description"
            spec.license = "MIT"
            spec.required_ruby_version = ">= 2.3.0"
            spec.require_paths = ["lib"]
            spec.bindir = "exe"
            spec.executables = ["templ"]
            # Namespace token example
            Kettle::Dev
          end
        GEMSPEC

        # Existing project gemspec with original values to be carried over
        File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = "0.1.0"
            spec.authors = ["Alice", "Bob"]
            spec.email = ["alice@example.com"]
            spec.summary = "Original summary"
            spec.description = "Original description more text"
            spec.license = "Apache-2.0"
            spec.required_ruby_version = ">= 3.2"
            spec.require_paths = ["lib", "ext"]
            spec.bindir = "bin"
            spec.executables = ["mygem", "mg"]
            spec.homepage = "https://github.com/acme/my-gem"
          end
        GEMSPEC

        allow(helpers).to receive_messages(
          project_root: project_root,
          gem_checkout_root: gem_root,
          ensure_clean_git!: nil,
          ask: true,
        )

        described_class.run

        dest = File.join(project_root, "my-gem.gemspec")
        expect(File).to exist(dest)
        txt = File.read(dest)

        # 1. name explicitly set to original
        expect(txt).to include('spec.name = "my-gem"')

        # 2-3. authors/email union (original, unique). We only assert presence of originals appended.
        expect(txt).to include('spec.authors = ["Alice", "Bob"]').or include('spec.authors = ["Bob", "Alice"]')
        expect(txt).not_to match(/spec.email\s*=\s*\[[^\]]*"template@example.com"[^\]]*\]/)
        expect(txt).to match(/spec.email\s*=\s*\[[^\]]*"alice@example.com"[^\]]*\]/)

        # 4-5. summary/description: original text carried over, prefixed with grapheme and a space
        expect(txt).to include('spec.summary = "Original summary"')
        expect(txt).to include('spec.description = "Original description more text"')

        # 6. license from original
        expect(txt).to include('spec.licenses = ["Apache-2.0"]')

        # 7. required_ruby_version from original
        expect(txt).to include('spec.required_ruby_version = ">= 3.2"')

        # 8. require_paths from original
        expect(txt).to include('spec.require_paths = ["lib", "ext"]')

        # 9. bindir from original
        expect(txt).to include('spec.bindir = "bin"')

        # 10. executables from original
        expect(txt).to include('spec.executables = ["mygem", "mg"]')
      end
    end
  end
end
