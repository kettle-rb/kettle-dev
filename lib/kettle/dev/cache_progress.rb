# frozen_string_literal: true

require "ruby-progressbar"

module Kettle
  module Dev
    class CacheProgress
      FORMAT = "%t %b %c/%C"
      LENGTH = 30

      def initialize(total:, cached_title:, live_title:, output:, enabled: true, skipped_title: nil)
        @total = total.to_i
        @cached_count = 0
        @live_count = 0
        @skipped_count = 0
        @cached_bar = progress_bar(cached_title, output, enabled)
        @live_bar = progress_bar(live_title, output, enabled)
        @skipped_bar = skipped_title ? progress_bar(skipped_title, output, enabled) : nil
      end

      attr_reader :cached_count, :live_count, :skipped_count

      def cached
        @cached_count += 1
        @cached_bar&.increment
      end

      def live
        @live_count += 1
        @live_bar&.increment
      end

      def skipped
        @skipped_count += 1
        @skipped_bar&.increment
      end

      private

      def progress_bar(title, output, enabled)
        return unless enabled
        return unless @total.positive?

        ProgressBar.create(title: title, total: @total, format: FORMAT, length: LENGTH, output: output)
      end
    end
  end
end
