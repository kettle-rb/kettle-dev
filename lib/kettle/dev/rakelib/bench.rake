require "rbconfig" if !Dir[File.join(__dir__, "benchmarks")].empty? # Used by `rake bench:run`

begin
  require "bundler"
rescue LoadError
  warn("[kettle-dev][bench.rake] failed to load bundler") if Kettle::Dev::DEBUGGING
  # ok, might still work
end

# --- Benchmarks (dev-only) ---
namespace :bench do
  desc "List available benchmark scripts"
  task :list do
    bench_files = Dir[File.join(__dir__, "benchmarks", "*.rb")].sort
    if bench_files.empty?
      puts "No benchmark scripts found under benchmarks/."
    else
      bench_files.each { |f| puts File.basename(f) }
    end
  end

  desc "Run all benchmark scripts (skips on CI)"
  task :run do
    if ENV.fetch("CI", "false").casecmp("true").zero?
      puts "Benchmarks are disabled on CI. Skipping."
      next
    end

    ruby = RbConfig.ruby
    bundle = Gem.bindir ? File.join(Gem.bindir, "bundle") : "bundle"
    bench_files = Dir[File.join(__dir__, "benchmarks", "*.rb")].sort
    if bench_files.empty?
      puts "No benchmark scripts found under benchmarks/."
      next
    end

    use_bundler = ENV.fetch("BENCH_BUNDLER", "0") == "1"

    bench_files.each do |script|
      puts "\n=== Running: #{File.basename(script)} ==="
      if use_bundler
        cmd = [bundle, "exec", ruby, "-Ilib", script]
        system(*cmd) || abort("Benchmark failed: #{script}")
      elsif defined?(Bundler)
        # Run benchmarks without Bundler to reduce overhead and better reflect plain ruby -Ilib
        Bundler.with_unbundled_env do
          system(ruby, "-Ilib", script) || abort("Benchmark failed: #{script}")
        end
      else
        # If Bundler isn't available, just run directly
        system(ruby, "-Ilib", script) || abort("Benchmark failed: #{script}")
      end
    end
  end
end

desc "Run all benchmarks (alias for bench:run)"
task bench: "bench:run"
