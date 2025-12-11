# frozen_string_literal: true

module Kettle
  module Dev
    # Prism-based AST merging for templated Ruby files.
    # Handles strategy dispatch (skip/replace/append/merge).
    #
    # Uses prism-merge for AST-aware merging with support for:
    # - Freeze blocks (kettle-dev:freeze / kettle-dev:unfreeze)
    # - Comment preservation
    # - Signature-based node matching
    #
    # @see Kettle::Jem::Presets for MergerConfig presets
    module SourceMerger
      BUG_URL = "https://github.com/kettle-rb/kettle-dev/issues"
      FREEZE_TOKEN = "kettle-dev"

      module_function

      # Apply a templating strategy to merge source and destination Ruby files
      #
      # @param strategy [Symbol] Merge strategy - :skip, :replace, :append, or :merge
      # @param src [String] Template source content
      # @param dest [String] Destination file content
      # @param path [String] File path (for error messages)
      # @param file_type [Symbol, nil] File type hint (:gemfile, :appraisals, :gemspec, :rakefile, nil)
      # @return [String] Merged content with comments preserved
      # @raise [Kettle::Dev::Error] If strategy is unknown or merge fails
      # @example
      #   SourceMerger.apply(
      #     strategy: :merge,
      #     src: 'gem "foo"',
      #     dest: 'gem "bar"',
      #     path: "Gemfile"
      #   )
      def apply(strategy:, src:, dest:, path:, file_type: nil)
        strategy = normalize_strategy(strategy)
        dest ||= ""
        src_content = src.to_s
        dest_content = dest
        detected_type = file_type || detect_file_type(path)

        result =
          case strategy
          when :skip
            # For skip, use merge to preserve freeze blocks (works with empty dest too)
            apply_merge(src_content, dest_content, file_type: detected_type)
          when :replace
            # For replace, use merge with template preference
            apply_merge(src_content, dest_content, file_type: detected_type)
          when :append
            # For append, use merge with destination preference
            apply_append(src_content, dest_content, file_type: detected_type)
          when :merge
            # For merge, use merge with template preference
            apply_merge(src_content, dest_content, file_type: detected_type)
          else
            raise Kettle::Dev::Error, "Unknown templating strategy '#{strategy}' for #{path}."
          end

        ensure_trailing_newline(result)
      rescue StandardError => error
        warn_bug(path, error)
        raise Kettle::Dev::Error, "Template merge failed for #{path}: #{error.message}"
      end

      # Detect file type from path for preset selection.
      #
      # @param path [String] File path
      # @return [Symbol] File type (:gemfile, :appraisals, :gemspec, :rakefile, or :ruby)
      # @api private
      def detect_file_type(path)
        basename = File.basename(path.to_s)
        case basename
        when /\AGemfile/, /\.gemfile\z/
          :gemfile
        when /\AAppraisals/
          :appraisals
        when /\.gemspec\z/
          :gemspec
        when /\ARakefile/, /\.rake\z/
          :rakefile
        else
          :ruby
        end
      end

      # Get the appropriate MergerConfig preset for a file type.
      #
      # @param file_type [Symbol] File type
      # @param preference [Symbol] :template or :destination
      # @return [Ast::Merge::MergerConfig] The config preset
      # @api private
      def config_for_file_type(file_type, preference:)
        require "kettle/jem" unless defined?(Kettle::Jem)

        preset_class = case file_type
                       when :gemfile
                         Kettle::Jem::Presets::Gemfile
                       when :appraisals
                         Kettle::Jem::Presets::Appraisals
                       when :gemspec
                         Kettle::Jem::Presets::Gemspec
                       when :rakefile
                         Kettle::Jem::Presets::Rakefile
                       else
                         Kettle::Jem::Presets::Gemfile # Default to Gemfile behavior
                       end

        if preference == :template
          preset_class.template_wins(freeze_token: FREEZE_TOKEN)
        else
          preset_class.destination_wins(freeze_token: FREEZE_TOKEN)
        end
      end

      # Get the appropriate MergerConfig preset for append strategy.
      #
      # Uses destination preference (existing content wins) but also adds
      # template-only nodes (content from source that doesn't exist in dest).
      #
      # @param file_type [Symbol] File type
      # @return [Ast::Merge::MergerConfig] The config preset
      # @api private
      def config_for_file_type_append(file_type)
        require "kettle/jem" unless defined?(Kettle::Jem)

        preset_class = case file_type
                       when :gemfile
                         Kettle::Jem::Presets::Gemfile
                       when :appraisals
                         Kettle::Jem::Presets::Appraisals
                       when :gemspec
                         Kettle::Jem::Presets::Gemspec
                       when :rakefile
                         Kettle::Jem::Presets::Rakefile
                       else
                         Kettle::Jem::Presets::Gemfile # Default to Gemfile behavior
                       end

        # For append: destination preference + add template-only nodes
        preset_class.custom(
          preference: :destination,
          add_template_only: true,
          freeze_token: FREEZE_TOKEN
        )
      end

      # Normalize strategy to a symbol
      #
      # @param strategy [Symbol, String, nil] Strategy to normalize
      # @return [Symbol] Normalized strategy (:skip if nil)
      # @api private
      def normalize_strategy(strategy)
        return :skip if strategy.nil?
        strategy.to_s.downcase.strip.to_sym
      end

      # Log error information for debugging
      #
      # @param path [String] File path that caused the error
      # @param error [StandardError] The error that occurred
      # @return [void]
      # @api private
      def warn_bug(path, error)
        puts "ERROR: kettle-dev templating failed for #{path}: #{error.message}"
        puts "Please file a bug at #{BUG_URL} with the file contents so we can improve the AST merger."
      end

      # Ensure text ends with exactly one newline
      #
      # @param text [String, nil] Text to process
      # @return [String] Text with trailing newline (empty string if nil)
      # @api private
      def ensure_trailing_newline(text)
        return "" if text.nil?
        text.end_with?("\n") ? text : text + "\n"
      end

      # Apply append strategy using prism-merge
      #
      # Uses destination preference for signature matching, which means
      # existing nodes in dest are preferred over template nodes.
      # Also enables add_template_only_nodes to append missing content from source.
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination content
      # @param file_type [Symbol] File type for preset selection
      # @return [String] Merged content
      # @api private
      def apply_append(src_content, dest_content, file_type: :ruby)
        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          puts "WARNING: prism-merge gem not available, falling back to source content"
          return src_content
        end

        # For append, we want destination preference but also add template-only nodes
        config = config_for_file_type_append(file_type)

        merger = Prism::Merge::SmartMerger.new(
          src_content,
          dest_content,
          **config.to_h
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for append strategy: #{e.message}"
        src_content
      end

      # Apply merge strategy using prism-merge
      #
      # Uses template preference for signature matching, which means
      # template nodes take precedence over existing destination nodes.
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination content
      # @param file_type [Symbol] File type for preset selection
      # @return [String] Merged content
      # @api private
      def apply_merge(src_content, dest_content, file_type: :ruby)
        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          puts "WARNING: prism-merge gem not available, falling back to source content"
          return src_content
        end

        config = config_for_file_type(file_type, preference: :template)

        merger = Prism::Merge::SmartMerger.new(
          src_content,
          dest_content,
          **config.to_h
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for merge strategy: #{e.message}"
        src_content
      end
    end
  end
end
