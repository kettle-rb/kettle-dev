#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug script to understand freeze block handling in gemspec merge

require "bundler/setup"
require "tree_sitter"

$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "kettle/dev"
$LOAD_PATH.unshift(File.expand_path('../../lib', __dir__))
require 'ast/merge'
$LOAD_PATH.unshift(File.expand_path('../dotenv-merge/lib', __dir__))
require 'dotenv/merge'
$LOAD_PATH.unshift(File.expand_path('../json-merge/lib', __dir__))
require 'json/merge'
$LOAD_PATH.unshift(File.expand_path('../kettle-jem/lib', __dir__))
require 'kettle/jem'
$LOAD_PATH.unshift(File.expand_path('../prism-merge/lib', __dir__))
require 'prism/merge'

fixture_dir = File.expand_path("spec/support/fixtures", __dir__)
dest_fixture = File.read(File.join(fixture_dir, "example-kettle-dev.gemspec"))
template_fixture = File.read(File.join(fixture_dir, "example-kettle-dev.template.gemspec"))

puts "=" * 80
puts "TEMPLATE FREEZE BLOCKS"
puts "=" * 80
template_fixture.each_line.with_index(1) do |line, num|
  if line =~ /kettle-dev:(freeze|unfreeze)/i
    puts "Line #{num}: #{line}"
  end
end

puts
puts "=" * 80
puts "DEST FREEZE BLOCKS"
puts "=" * 80
dest_fixture.each_line.with_index(1) do |line, num|
  if line =~ /kettle-dev:(freeze|unfreeze)/i
    puts "Line #{num}: #{line}"
  end
end

puts
puts "=" * 80
puts "ANALYZING TEMPLATE (Prism::Merge::FileAnalysis)"
puts "=" * 80

template_analysis = Prism::Merge::FileAnalysis.new(
  template_fixture,
  freeze_token: "kettle-dev"
)

puts "Template statements count: #{template_analysis.statements.length}"
template_analysis.statements.each_with_index do |node, i|
  sig = template_analysis.generate_signature(node)
  puts "  #{i}: #{node.class.name.split('::').last} -> sig=#{sig.inspect[0..100]}"
end

puts
puts "=" * 80
puts "ANALYZING DEST (Prism::Merge::FileAnalysis)"
puts "=" * 80

dest_analysis = Prism::Merge::FileAnalysis.new(
  dest_fixture,
  freeze_token: "kettle-dev"
)

puts "Dest statements count: #{dest_analysis.statements.length}"
dest_analysis.statements.each_with_index do |node, i|
  sig = dest_analysis.generate_signature(node)
  puts "  #{i}: #{node.class.name.split('::').last} -> sig=#{sig.inspect[0..100]}"
end

# Find freeze blocks in both
template_freeze_blocks = template_analysis.statements.select { |n| n.is_a?(Ast::Merge::FreezeNodeBase) }
dest_freeze_blocks = dest_analysis.statements.select { |n| n.is_a?(Ast::Merge::FreezeNodeBase) }

puts
puts "=" * 80
puts "FREEZE BLOCK SIGNATURES"
puts "=" * 80

puts "Template freeze blocks (#{template_freeze_blocks.length}):"
template_freeze_blocks.each do |fb|
  sig = fb.signature
  puts "  Lines #{fb.start_line}-#{fb.end_line}: #{sig.inspect}"
end

puts
puts "Dest freeze blocks (#{dest_freeze_blocks.length}):"
dest_freeze_blocks.each do |fb|
  sig = fb.signature
  puts "  Lines #{fb.start_line}-#{fb.end_line}: #{sig.inspect}"
end

# Check if first freeze blocks match
if template_freeze_blocks.any? && dest_freeze_blocks.any?
  template_sig = template_freeze_blocks.first.signature
  dest_sig = dest_freeze_blocks.first.signature
  puts
  puts "First freeze block signatures match: #{template_sig == dest_sig}"
  if template_sig != dest_sig
    puts "  Template: #{template_sig.inspect}"
    puts "  Dest:     #{dest_sig.inspect}"
  end
end

puts
puts "=" * 80
puts "PERFORMING MERGE (Direct Prism::Merge::SmartMerger)"
puts "=" * 80

# First, test with SmartMerger directly
smart_merger = Prism::Merge::SmartMerger.new(
  template_fixture,
  dest_fixture,
  freeze_token: "kettle-dev"
)
simple_merged = smart_merger.merge

puts "SmartMerger result:"
freeze_count_simple = 0
simple_merged.each_line.with_index(1) do |line, num|
  if line =~ /kettle-dev:(freeze|unfreeze)/i
    freeze_count_simple += 1
    puts "  Line #{num}: #{line}"
  end
end
puts "  SmartMerger freeze marker count: #{simple_merged.scan(/kettle-dev:freeze/i).length}"

puts
puts "=" * 80
puts "PERFORMING MERGE (via Kettle::Dev::SourceMerger)"
puts "=" * 80

merged = Kettle::Dev::SourceMerger.apply(
  strategy: :merge,
  src: template_fixture,
  dest: dest_fixture,
  path: "example-kettle-dev.gemspec",
)

puts
puts "=" * 80
puts "MERGED RESULT - FREEZE MARKERS"
puts "=" * 80
freeze_count = 0
merged.each_line.with_index(1) do |line, num|
  if line =~ /kettle-dev:(freeze|unfreeze)/i
    freeze_count += 1
    puts "Line #{num}: #{line}"
  end
end

puts
puts "Total freeze/unfreeze markers: #{freeze_count}"
puts "Expected: 4 (2 freeze + 2 unfreeze)"
puts "Freeze marker count (freeze only): #{merged.scan(/kettle-dev:freeze/i).length}"
