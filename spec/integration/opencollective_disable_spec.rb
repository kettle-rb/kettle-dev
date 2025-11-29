# frozen_string_literal: true

RSpec.describe "Open Collective Disable Functionality" do # rubocop:disable RSpec/DescribeClass
  describe "Kettle::Dev::TemplateHelpers" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    describe ".opencollective_disabled?" do
      context "when OPENCOLLECTIVE_HANDLE is set to false" do
        it "returns true for 'false' (case-insensitive)" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for 'False'" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "False")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for 'FALSE'" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "FALSE")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for 'no'" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "no")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for 'NO'" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "NO")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for '0'" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "0")
          expect(helpers.opencollective_disabled?).to be true
        end
      end

      context "when FUNDING_ORG is set to false" do
        it "returns true for 'false'" do
          stub_env("FUNDING_ORG" => "false")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for 'no'" do
          stub_env("FUNDING_ORG" => "no")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true for '0'" do
          stub_env("FUNDING_ORG" => "0")
          expect(helpers.opencollective_disabled?).to be true
        end
      end

      context "when either variable is set to false" do
        it "returns true when OPENCOLLECTIVE_HANDLE is false and FUNDING_ORG is unset" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false", "FUNDING_ORG" => nil)
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true when FUNDING_ORG is false and OPENCOLLECTIVE_HANDLE is unset" do
          stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => "false")
          expect(helpers.opencollective_disabled?).to be true
        end

        it "returns true when both are set to false" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false", "FUNDING_ORG" => "false")
          expect(helpers.opencollective_disabled?).to be true
        end
      end

      context "when variables are not set to falsey values" do
        it "returns false when variables are unset" do
          stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => nil)
          expect(helpers.opencollective_disabled?).to be false
        end

        it "returns false when variables are empty strings" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "", "FUNDING_ORG" => "")
          expect(helpers.opencollective_disabled?).to be false
        end

        it "returns false when set to a valid org name" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "my-org", "FUNDING_ORG" => nil)
          expect(helpers.opencollective_disabled?).to be false
        end

        it "returns false when set to any other value" do
          stub_env("OPENCOLLECTIVE_HANDLE" => "true", "FUNDING_ORG" => nil)
          expect(helpers.opencollective_disabled?).to be false
        end
      end
    end

    describe ".skip_for_disabled_opencollective?" do
      context "when opencollective is disabled" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false")
        end

        it "returns true for .opencollective.yml" do
          expect(helpers.skip_for_disabled_opencollective?(".opencollective.yml")).to be true
        end

        it "returns true for .github/workflows/opencollective.yml" do
          expect(helpers.skip_for_disabled_opencollective?(".github/workflows/opencollective.yml")).to be true
        end

        it "returns false for other files" do
          expect(helpers.skip_for_disabled_opencollective?("README.md")).to be false
          expect(helpers.skip_for_disabled_opencollective?("FUNDING.md")).to be false
          expect(helpers.skip_for_disabled_opencollective?(".github/FUNDING.yml")).to be false
          expect(helpers.skip_for_disabled_opencollective?(".github/workflows/ci.yml")).to be false
        end
      end

      context "when opencollective is not disabled" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => nil)
        end

        it "returns false for all files including opencollective files" do
          expect(helpers.skip_for_disabled_opencollective?(".opencollective.yml")).to be false
          expect(helpers.skip_for_disabled_opencollective?(".github/workflows/opencollective.yml")).to be false
        end
      end
    end

    describe ".prefer_example_with_osc_check" do
      around do |example|
        Dir.mktmpdir do |dir|
          @tmpdir = dir
          example.run
        end
      end

      context "when opencollective is disabled" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false")
        end

        it "prefers .no-osc.example when it exists" do
          regular = File.join(@tmpdir, "README.md")
          example = File.join(@tmpdir, "README.md.example")
          no_osc = File.join(@tmpdir, "README.md.no-osc.example")

          File.write(regular, "regular")
          File.write(example, "example")
          File.write(no_osc, "no-osc")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(no_osc)
        end

        it "falls back to .example when .no-osc.example does not exist" do
          regular = File.join(@tmpdir, "Rakefile")
          example = File.join(@tmpdir, "Rakefile.example")

          File.write(regular, "regular")
          File.write(example, "example")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(example)
        end

        it "returns the original path when neither .no-osc.example nor .example exist" do
          regular = File.join(@tmpdir, "somefile.txt")
          File.write(regular, "regular")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(regular)
        end

        it "handles paths that already end with .example" do
          example = File.join(@tmpdir, "file.example")
          no_osc = File.join(@tmpdir, "file.no-osc.example")

          File.write(example, "example")
          File.write(no_osc, "no-osc")

          result = helpers.prefer_example_with_osc_check(example)
          expect(result).to eq(no_osc)
        end
      end

      context "when opencollective is not disabled" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => nil)
        end

        it "prefers .example over .no-osc.example" do
          regular = File.join(@tmpdir, "README.md")
          example = File.join(@tmpdir, "README.md.example")
          no_osc = File.join(@tmpdir, "README.md.no-osc.example")

          File.write(regular, "regular")
          File.write(example, "example")
          File.write(no_osc, "no-osc")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(example)
        end

        it "returns .example when it exists" do
          regular = File.join(@tmpdir, "FUNDING.md")
          example = File.join(@tmpdir, "FUNDING.md.example")

          File.write(regular, "regular")
          File.write(example, "example")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(example)
        end

        it "returns the original path when .example does not exist" do
          regular = File.join(@tmpdir, "somefile.txt")
          File.write(regular, "regular")

          result = helpers.prefer_example_with_osc_check(regular)
          expect(result).to eq(regular)
        end
      end
    end
  end

  describe "Kettle::Dev::GemSpecReader" do
    let(:reader) { Kettle::Dev::GemSpecReader }

    around do |example|
      Dir.mktmpdir do |dir|
        @tmpdir = dir
        example.run
      end
    end

    def create_minimal_gemspec(dir, gem_name, options = {})
      gemspec_path = File.join(dir, "#{gem_name}.gemspec")
      homepage = options[:homepage] || "https://github.com/test-org/#{gem_name}"

      File.write(gemspec_path, <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "#{gem_name}"
          spec.version = "1.0.0"
          spec.authors = ["Test Author"]
          spec.email = ["test@example.com"]
          spec.summary = "Test gem"
          spec.description = "Test gem description"
          spec.homepage = "#{homepage}"
          spec.required_ruby_version = ">= 2.7.0"
        end
      RUBY

      gemspec_path
    end

    describe ".load with OPENCOLLECTIVE_HANDLE=false" do
      context "when OPENCOLLECTIVE_HANDLE is set to false" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "false", "FUNDING_ORG" => nil)
        end

        it "sets funding_org to nil" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to be_nil
        end

        it "sets funding_org to nil even when .opencollective.yml exists" do
          create_minimal_gemspec(@tmpdir, "test-gem")
          File.write(File.join(@tmpdir, ".opencollective.yml"), "collective: my-org\n")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to be_nil
        end
      end

      context "when FUNDING_ORG is set to false" do
        before do
          stub_env("FUNDING_ORG" => "false", "OPENCOLLECTIVE_HANDLE" => nil)
        end

        it "sets funding_org to nil" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to be_nil
        end
      end

      context "when OPENCOLLECTIVE_HANDLE is set to 'no'" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "no")
        end

        it "sets funding_org to nil" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to be_nil
        end
      end

      context "when OPENCOLLECTIVE_HANDLE is set to '0'" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "0")
        end

        it "sets funding_org to nil" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to be_nil
        end
      end
    end

    describe ".load with OPENCOLLECTIVE_HANDLE enabled" do
      context "when OPENCOLLECTIVE_HANDLE is set to a valid org name" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => "my-collective", "FUNDING_ORG" => nil)
        end

        it "uses the OPENCOLLECTIVE_HANDLE value" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to eq("my-collective")
        end
      end

      context "when FUNDING_ORG is set to a valid org name" do
        before do
          stub_env("FUNDING_ORG" => "my-org", "OPENCOLLECTIVE_HANDLE" => nil)
        end

        it "uses the FUNDING_ORG value" do
          create_minimal_gemspec(@tmpdir, "test-gem")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to eq("my-org")
        end
      end

      context "when .opencollective.yml exists" do
        before do
          stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => nil)
        end

        it "reads the collective from the YAML file" do
          create_minimal_gemspec(@tmpdir, "test-gem")
          File.write(File.join(@tmpdir, ".opencollective.yml"), "collective: yaml-org\n")

          result = reader.load(@tmpdir)
          expect(result[:funding_org]).to eq("yaml-org")
        end
      end
    end
  end
end
