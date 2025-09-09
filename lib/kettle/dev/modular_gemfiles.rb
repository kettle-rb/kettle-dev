# frozen_string_literal: true

module Kettle
  module Dev
    # Utilities for copying modular Gemfiles and related directories
    # in a DRY fashion. Used by both the template rake task and the
    # setup CLI to ensure gemfiles/modular/* are present before use.
    module ModularGemfiles
      MODULAR_GEMFILE_DIR = "gemfiles/modular"

      module_function

      # Copy the modular gemfiles and nested directories from the gem
      # checkout into the target project, prompting where appropriate
      # via the provided helpers.
      #
      # @param helpers [Kettle::Dev::TemplateHelpers] helper API
      # @param project_root [String] destination project root
      # @param gem_checkout_root [String] kettle-dev checkout root (source)
      # @param min_ruby [Gem::Version, nil] minimum Ruby version (for style.gemfile tuning)
      # @return [void]
      def sync!(helpers:, project_root:, gem_checkout_root:, min_ruby: nil)
        # 4a) gemfiles/modular/*.gemfile except style.gemfile (handled below)
        modular_gemfiles = %w[
          coverage
          debug
          documentation
          injected
          optional
          runtime_heads
          x_std_libs
        ]
        modular_gemfiles.each do |base|
          modular_gemfile = "#{base}.gemfile"
          src = helpers.prefer_example(File.join(gem_checkout_root, MODULAR_GEMFILE_DIR, modular_gemfile))
          dest = File.join(project_root, MODULAR_GEMFILE_DIR, modular_gemfile)
          helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        end

        # 4b) gemfiles/modular/style.gemfile with dynamic rubocop constraints
        modular_gemfile = "style.gemfile"
        src = helpers.prefer_example(File.join(gem_checkout_root, MODULAR_GEMFILE_DIR, modular_gemfile))
        dest = File.join(project_root, MODULAR_GEMFILE_DIR, modular_gemfile)
        if File.basename(src).sub(/\.example\z/, "") == "style.gemfile"
          helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
            # Adjust rubocop-lts constraint based on min_ruby
            version_map = [
              [Gem::Version.new("1.8"), "~> 0.1"],
              [Gem::Version.new("1.9"), "~> 2.0"],
              [Gem::Version.new("2.0"), "~> 4.0"],
              [Gem::Version.new("2.1"), "~> 6.0"],
              [Gem::Version.new("2.2"), "~> 8.0"],
              [Gem::Version.new("2.3"), "~> 10.0"],
              [Gem::Version.new("2.4"), "~> 12.0"],
              [Gem::Version.new("2.5"), "~> 14.0"],
              [Gem::Version.new("2.6"), "~> 16.0"],
              [Gem::Version.new("2.7"), "~> 18.0"],
              [Gem::Version.new("3.0"), "~> 20.0"],
              [Gem::Version.new("3.1"), "~> 22.0"],
              [Gem::Version.new("3.2"), "~> 24.0"],
              [Gem::Version.new("3.3"), "~> 26.0"],
              [Gem::Version.new("3.4"), "~> 28.0"],
            ]
            new_constraint = nil
            rubocop_ruby_gem_version = nil
            ruby1_8 = version_map.first
            begin
              if min_ruby
                version_map.reverse_each do |min, req|
                  if min_ruby >= min
                    new_constraint = req
                    rubocop_ruby_gem_version = min.segments.join("_")
                    break
                  end
                end
              end
              if !new_constraint || !rubocop_ruby_gem_version
                # A gem with no declared minimum ruby is effectively >= 1.8.7
                new_constraint = ruby1_8[1]
                rubocop_ruby_gem_version = ruby1_8[0].segments.join("_")
              end
            rescue StandardError => e
              Kettle::Dev.debug_error(e, __method__) if defined?(Kettle::Dev.debug_error)
              # ignore, use default
            ensure
              new_constraint ||= ruby1_8[1]
              rubocop_ruby_gem_version ||= ruby1_8[0].segments.join("_")
            end
            if new_constraint && rubocop_ruby_gem_version
              token = "{RUBOCOP|LTS|CONSTRAINT}"
              content.gsub!(token, new_constraint) if content.include?(token)
              token = "{RUBOCOP|RUBY|GEM}"
              content.gsub!(token, "rubocop-ruby#{rubocop_ruby_gem_version}") if content.include?(token)
            end
            content
          end
        else
          helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        end

        # 4c) Copy modular directories with nested/versioned files
        %w[erb mutex_m stringio x_std_libs].each do |dir|
          src_dir = File.join(gem_checkout_root, MODULAR_GEMFILE_DIR, dir)
          dest_dir = File.join(project_root, MODULAR_GEMFILE_DIR, dir)
          helpers.copy_dir_with_prompt(src_dir, dest_dir)
        end
      end
    end
  end
end
