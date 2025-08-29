# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  let(:ci_helpers) { Kettle::Dev::CIHelpers }

  describe "copyright years validation" do
    it "passes when README.md and LICENSE.txt have identical year sets and include current year" do
      Dir.mktmpdir do |root|
        # Minimal files
        File.write(File.join(root, "README.md"), <<~MD)
          # Title
          \n
          ### © Copyright
          \n
          Copyright (c) 2023-2025 Example
        MD
        File.write(File.join(root, "LICENSE.txt"), <<~MD)
          The MIT License (MIT)

          Copyright (c) 2023, 2024, 2025 Example
        MD
        allow(ci_helpers).to receive(:project_root).and_return(root)

        cli = described_class.new
        # Should not abort
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
      end
    end

    it "rewrites consecutive years into a range in both files" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "README.md"), "Copyright (c) 2023, 2024, 2025 Example")
        File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) 2023, 2024, 2025 Example")
        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        # After validation, files should have collapsed range
        expect(File.read(File.join(root, "README.md"))).to include("2023-2025")
        expect(File.read(File.join(root, "LICENSE.txt"))).to include("2023-2025")
      end
    end

    it "aborts when sets differ (mismatch)" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "README.md"), <<~MD)
          Copyright (c) 2023, 2025 Example
        MD
        File.write(File.join(root, "LICENSE.txt"), <<~MD)
          The MIT License (MIT)
          Copyright 2023-2024 Example
        MD
        allow(ci_helpers).to receive(:project_root).and_return(root)

        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.to raise_error(MockSystemExit, /Mismatched copyright years/)
      end
    end

    it "is skipped silently if either file is missing" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "README.md"), "Copyright (c) 2024")
        # No LICENSE.txt
        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
      end
    end

    it "injects current year into both files when missing and sets match" do
      Dir.mktmpdir do |root|
        current_year = Time.now.year
        last_year = current_year - 1
        # Both have exactly last_year only -> sets match but missing current year
        File.write(File.join(root, "README.md"), "Copyright (c) #{last_year} Example")
        File.write(File.join(root, "LICENSE.txt"), "The MIT License (MIT)\nCopyright (c) #{last_year} Example")
        allow(ci_helpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:validate_copyright_years!) }.not_to raise_error
        # Should now include a range last_year-current_year in both files
        expect(File.read(File.join(root, "README.md"))).to include("#{last_year}-#{current_year}")
        expect(File.read(File.join(root, "LICENSE.txt"))).to include("#{last_year}-#{current_year}")
      end
    end
  end
end
