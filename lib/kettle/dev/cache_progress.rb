# frozen_string_literal: true

require "tty-progressbar"

module Kettle
  module Dev
    class CacheProgress
      FORMAT = "%<title>s [:bar] :current/:total"
      WIDTH = 30

      def initialize(total:, cached_title:, live_title:, output:, enabled: true, skipped_title: nil)
        @total = total.to_i
        @cached_count = 0
        @live_count = 0
        @skipped_count = 0
        @multibar = progress_enabled?(enabled, output) ? TTY::ProgressBar::Multi.new(output: output, width: WIDTH) : nil
        @cached_bar = progress_bar(cached_title)
        @live_bar = progress_bar(live_title)
        @skipped_bar = skipped_title ? progress_bar(skipped_title) : nil
      end

      attr_reader :cached_count, :live_count, :skipped_count

      def cached
        @cached_count += 1
        @cached_bar&.advance
      end

      def live
        @live_count += 1
        @live_bar&.advance
      end

      def skipped
        @skipped_count += 1
        @skipped_bar&.advance
      end

      def stop
        @multibar&.stop
      end

      private

      def progress_enabled?(enabled, output)
        enabled && @total.positive? && output.respond_to?(:tty?) && output.tty?
      end

      def progress_bar(title)
        return unless @multibar
        return unless @total.positive?

        @multibar.register(bar_format(title), total: @total)
      end

      def bar_format(title)
        Kernel.format(FORMAT, title: title)
      end
    end
  end
end
