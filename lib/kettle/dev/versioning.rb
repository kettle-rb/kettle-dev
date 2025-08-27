# frozen_string_literal: true

module Kettle
  module Dev
    # Shared helpers for version detection and bump classification.
    module Versioning
      module_function

      # Detects a unique VERSION constant declared under lib/**/version.rb
      # @param root [String] project root
      # @return [String] version string
      def detect_version(root)
        candidates = Dir[File.join(root, "lib", "**", "version.rb")]
        abort!("Could not find version.rb under lib/**.") if candidates.empty?
        versions = candidates.map do |path|
          content = File.read(path)
          m = content.match(/VERSION\s*=\s*(["'])([^"']+)\1/)
          next unless m
          m[2]
        end.compact
        abort!("VERSION constant not found in #{root}/lib/**/version.rb") if versions.none?
        abort!("Multiple VERSION constants found to be out of sync (#{versions.inspect}) in #{root}/lib/**/version.rb") unless versions.uniq.length == 1
        versions.first
      end

      # Classify the bump type from prev -> cur.
      # EPIC is a MAJOR > 1000.
      # @param prev [String] previous released version
      # @param cur [String] current version (from version.rb)
      # @return [Symbol] one of :epic, :major, :minor, :patch, :same, :downgrade
      def classify_bump(prev, cur)
        pv = Gem::Version.new(prev)
        cv = Gem::Version.new(cur)
        return :same if cv == pv
        return :downgrade if cv < pv

        pmaj, pmin, ppatch = (pv.segments + [0, 0, 0])[0, 3]
        cmaj, cmin, cpatch = (cv.segments + [0, 0, 0])[0, 3]

        if cmaj > pmaj
          return :epic if cmaj && cmaj > 1000
          return :major
        elsif cmin > pmin
          return :minor
        elsif cpatch > ppatch
          return :patch
        else
          # Fallback; should be covered by :same above, but in case of weird segment shapes
          :same
        end
      end

      # Whether MAJOR is an EPIC version (strictly > 1000)
      # @param major [Integer]
      # @return [Boolean]
      def epic_major?(major)
        major && major > 1000
      end

      # Abort via ExitAdapter if available; otherwise Kernel.abort
      # @param msg [String]
      # @return [void]
      def abort!(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      rescue StandardError
        Kernel.abort(msg)
      end
    end
  end
end
