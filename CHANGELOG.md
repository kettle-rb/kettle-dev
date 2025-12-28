# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- New `kettle-gh-release` executable for standalone GitHub release creation
  - Extracted from `kettle-release` step 18
  - Useful when RubyGems release succeeded but GitHub release failed
  - Supports explicit version via `version=<VERSION>` argument
  - Auto-detects version from `lib/**/version.rb` if not specified
  - Requires `GITHUB_TOKEN` with `repo:public_repo` (classic) or `contents:write` scope
- Added `.kettle-dev.yml` configuration file for per-file merge options
  - Hybrid format: `defaults` for shared merge options, `patterns` for glob fallbacks, `files` for per-file config
  - Nested directory structure under `files` allows individual file configuration
  - Supports all `Prism::Merge::SmartMerger` options: `preference`, `add_template_only_nodes`, `freeze_token`, `max_recursion_depth`
  - Added `TemplateHelpers.kettle_config`, `.config_for`, `.find_file_config` methods
  - Added spec coverage in `template_helpers_config_spec.rb`

### Changed

- **BREAKING**: Replaced `template_manifest.yml` with `.kettle-dev.yml`
  - New hybrid format supports both glob patterns and per-file configuration
  - `TemplateHelpers.load_manifest` now reads from `.kettle-dev.yml` patterns section
  - `TemplateHelpers.strategy_for` checks explicit file configs before falling back to patterns
- **BREAKING**: Simplified `SourceMerger` to fully rely on prism-merge for AST merging
  - Reduced from ~610 lines to ~175 lines (71% reduction)
  - Removed custom newline normalization - prism-merge preserves original formatting
  - Removed custom comment deduplication logic - prism-merge handles this natively
  - All strategies (`:skip`, `:replace`, `:append`, `:merge`) now use prism-merge consistently
  - Freeze blocks (`kettle-dev:freeze` / `kettle-dev:unfreeze`) handled by prism-merge's `freeze_token` option

### Deprecated

### Removed

- Removed unused methods from `SourceMerger`:
  - `normalize_source` - replaced by prism-merge
  - `normalize_newlines` - prism-merge preserves original formatting
  - `shebang?`, `magic_comment?`, `ruby_magic_comment_key?` - no longer needed
  - Comment extraction/deduplication: `extract_magic_comments`, `extract_file_leading_comments`,
    `create_comment_tuples`, `deduplicate_comment_sequences`, `deduplicate_sequences_pass1`,
    `deduplicate_singles_pass2`, `extract_nodes_with_comments`, `count_blank_lines_before`,
    `build_source_from_nodes`
  - Unused comment restoration: `restore_custom_leading_comments`, `deduplicate_leading_comment_block`,
    `extract_comment_lines`, `normalize_comment`, `leading_comment_block`
- Removed unused constants: `RUBY_MAGIC_COMMENT_KEYS`, `MAGIC_COMMENT_REGEXES`

### Fixed

- Fixed `PrismAppraisals` various comment chunk spacing
  - extract_block_header:
    - skips the blank spacer immediately above an `appraise` block
    - treats any following blank line as the stop boundary once comment lines have been collected
    - prevents preamble comments from being pulled into the first block’s header
  - restores expected ordering:
    - magic comments and their blank line stay at the top
    - block headers remain adjacent to their blocks
    - preserves blank lines between comment chunks
- Fixed `SourceMerger` freeze block location preservation
  - Freeze blocks now stay in their original location in the file structure
  - Skip normalization for files with existing freeze blocks to prevent movement
  - Only include contiguous comments immediately before freeze markers (no arbitrary 3-line lookback)
  - Don't add freeze reminder to files that already have freeze/unfreeze blocks
  - Prevents unrelated comments from being incorrectly captured in freeze block ranges
  - Added comprehensive test coverage for multiple freeze blocks at different nesting levels
- Fixed `TemplateTask` to not override template summary/description with empty strings from destination gemspec
  - Only carries over summary/description when they contain actual content (non-empty)
  - Allows token replacements to work correctly (e.g., `kettle-dev summary` → `my-gem summary`)
  - Prevents empty destination fields from erasing meaningful template values
- Fixed `SourceMerger` magic comment ordering and freeze block protection
  - Magic comments now preserve original order
  - No blank lines inserted between consecutive magic comments
  - Freeze reminder block properly separated from magic comments (not merged)
  - Leverages Prism's built-in `parse_result.magic_comments` API for accurate detection
  - Detects `kettle-dev:freeze/unfreeze` pairs using Prism, then reclassifies as file-level comments to keep blocks intact
  - Removed obsolete `is_magic_comment?` method in favor of Prism's native detection
- Fixed `PrismGemspec` and `PrismGemfile` to use pure Prism AST traversal instead of regex fallbacks
  - Removed regex-based `extract_gemspec_emoji` that parsed `spec.summary =` and `spec.description =` with regex
  - Now traverses Prism AST to find Gem::Specification block, extracts summary/description nodes, and gets literal values
  - Removed regex-based source line detection in `PrismGemfile.merge_gem_calls`
  - Now uses `PrismUtils.statement_key` to find source statements via AST instead of `ln =~ /^\s*source\s+/`
  - Aligns with project goal: move away from regex parsing toward proper AST manipulation with Prism
  - All functionality preserved, tested, and working correctly
- Fixed `PrismGemspec.replace_gemspec_fields` block parameter extraction to use Prism AST
  - **CRITICAL**: Was using regex fallback that incorrectly captured entire block body as parameter name
  - Removed buggy regex fallback in favor of pure Prism AST traversal
  - Now properly extracts block parameter from Prism::BlockParametersNode → Prism::ParametersNode → Prism::RequiredParameterNode
- Fixed `PrismGemspec.replace_gemspec_fields` insert offset calculation for emoji-containing gemspecs
  - **CRITICAL**: Was using character length (`String#length`) instead of byte length (`String#bytesize`) to calculate insert offset
  - When gemspecs contain multi-byte UTF-8 characters (emojis like 🍲), character length != byte length
  - This caused fields to be inserted at wrong byte positions, resulting in truncated strings and massive corruption
  - Changed `body_src.rstrip.length` to `body_src.rstrip.bytesize` for correct byte-offset calculations
  - Prevents gemspec templating from producing corrupted output with truncated dependency lines
  - Added comprehensive debug logging to trace byte offset calculations and edit operations
- Fixed `SourceMerger` variable assignment duplication during merge operations
  - `node_signature` now identifies variable/constant assignments by name only, not full source
  - Previously used full source text as signature, causing duplicates when assignment bodies differed
  - Added specific handlers for: LocalVariableWriteNode, InstanceVariableWriteNode, ClassVariableWriteNode, ConstantWriteNode, GlobalVariableWriteNode
  - Also added handlers for ClassNode and ModuleNode to match by name
  - Example: `gem_version = ...` assignments with different bodies now correctly merge instead of duplicating
  - Prevents `bin/kettle-dev-setup` from creating duplicate variable assignments in gemspecs and other files
  - Added comprehensive specs for variable assignment deduplication and idempotency
- Fixed `SourceMerger` conditional block duplication during merge operations
  - `node_signature` now identifies conditional nodes (if/unless/case) by their predicate only
  - Previously used full source text, causing duplicate blocks when template updates conditional bodies
  - Example: if ENV["FOO"] blocks with different bodies now correctly merge instead of duplicating
  - Prevents `bin/kettle-dev-setup` from creating duplicate if/else blocks in gemfiles
  - Added comprehensive specs for conditional merging behavior and idempotency
- Fixed `PrismGemspec.replace_gemspec_fields` to use byte-aware string operations
  - **CRITICAL**: Was using character-based `String#[]=` with Prism's byte offsets
  - This caused catastrophic corruption when emojis or multi-byte UTF-8 characters were present
  - Symptoms: gemspec blocks duplicated/fragmented, statements escaped outside blocks
  - Now uses `byteslice` and byte-aware concatenation for all edit operations
  - Prevents gemspec templating from producing mangled output with duplicated Gem::Specification blocks
- Fixed `PrismGemspec.replace_gemspec_fields` to correctly handle multi-byte UTF-8 characters (e.g., emojis)
  - Prism uses byte offsets, not character offsets, when parsing Ruby code
  - Changed string slicing from `String#[]` to `String#byteslice` for all offset-based operations
  - Added validation to use `String#bytesize` instead of `String#length` for offset bounds checking
  - Prevents `TypeError: no implicit conversion of nil into String` when gemspecs contain emojis
  - Ensures gemspec field carryover works correctly with emoji in summary/description fields
  - Enhanced error reporting to show backtraces when debug mode is enabled

### Security

## [1.2.5] - 2025-11-28

- TAG: [v1.2.5][1.2.5t]
- COVERAGE: 93.53% -- 4726/5053 lines in 31 files
- BRANCH COVERAGE: 76.62% -- 1924/2511 branches in 31 files
- 69.89% documented

### Added

- Comprehensive newline normalization in templated Ruby files:
  - Magic comments (frozen_string_literal, encoding, etc.) always followed by single blank line
  - No more than one consecutive blank line anywhere in file
  - Single newline at end of file (no trailing blank lines)
  - Freeze reminder block now includes blank line before and empty comment line after for better visual separation

### Changed

- Updated `FREEZE_REMINDER` constant to include blank line before and empty comment line after

### Fixed

- Fixed `reminder_present?` to correctly detect freeze reminder when it has leading blank line

## [1.2.4] - 2025-11-28

- TAG: [v1.2.4][1.2.4t]
- COVERAGE: 93.53% -- 4701/5026 lines in 31 files
- BRANCH COVERAGE: 76.61% -- 1913/2497 branches in 31 files
- 69.78% documented

### Fixed

- Fixed comment deduplication in `restore_custom_leading_comments` to prevent accumulation across multiple template runs
  - Comments from destination are now deduplicated before being merged back into result
  - Fixes issue where `:replace` strategy (used by `kettle-dev-setup --force`) would accumulate duplicate comments
  - Ensures truly idempotent behavior when running templating multiple times on the same file
  - Example: `frozen_string_literal` comments no longer multiply from 1→4→5→6 on repeated runs

## [1.2.3] - 2025-11-28vari

- TAG: [v1.2.3][1.2.3t]
- COVERAGE: 93.43% -- 4681/5010 lines in 31 files
- BRANCH COVERAGE: 76.63% -- 1912/2495 branches in 31 files
- 70.55% documented

### Fixed

- Fixed Gemfile parsing to properly deduplicate comments across multiple template runs
  - Implemented two-pass comment deduplication: sequences first, then individual lines
  - Magic comments (frozen_string_literal, encoding, etc.) are now properly deduplicated by content, not line position
  - File-level comments are deduplicated while preserving leading comments attached to statements
  - Ensures idempotent behavior when running templating multiple times on the same file
  - Prevents accumulation of duplicate frozen_string_literal comments and comment blocks

## [1.2.2] - 2025-11-27

- TAG: [v1.2.2][1.2.2t]
- COVERAGE: 93.28% -- 4596/4927 lines in 31 files
- BRANCH COVERAGE: 76.45% -- 1883/2463 branches in 31 files
- 70.00% documented

### Added

- Prism AST-based manipulation of ruby during templating
  - Gemfiles
  - gemspecs
  - .simplecov
- Stop rescuing Exception in certain scenarios (just StandardError)
- Refactored logging logic and documentation
- Prevent self-referential gemfile injection
  - in Gemfiles, gemspecs, and Appraisals
- Improve reliability of coverage and documentation stats
  - in the changelog version heading
  - fails hard when unable to generate stats, unless `--no-strict` provided

## [1.2.1] - 2025-11-25

- TAG: [v1.2.0][1.2.0t]
- COVERAGE: 94.38% -- 4066/4308 lines in 26 files
- BRANCH COVERAGE: 78.81% -- 1674/2124 branches in 26 files
- 69.14% documented

### Changed

- Source merging switched from Regex-based string manipulation to Prism AST-based manipulation
  - Comments are preserved in the resulting file

## [1.1.60] - 2025-11-23

- TAG: [v1.1.60][1.1.60t]
- COVERAGE: 94.38% -- 4066/4308 lines in 26 files
- BRANCH COVERAGE: 78.86% -- 1675/2124 branches in 26 files
- 79.89% documented

### Added

- Add KETTLE_DEV_DEBUG to direnv defaults
- Documentation of the explicit policy violations of RubyGems.org leadership toward open source projects they funded
  - https://www.reddit.com/r/ruby/comments/1ove9vp/rubycentral_hates_this_one_fact/

### Fixed

- Prevent double test runs by ensuring only one of test/coverage/spec are in default task
  - Add debugging when more than one registered

## [1.1.59] - 2025-11-13

- TAG: [v1.1.59][1.1.59t]
- COVERAGE: 94.38% -- 4066/4308 lines in 26 files
- BRANCH COVERAGE: 78.77% -- 1673/2124 branches in 26 files
- 79.89% documented

### Changed

- Improved default devcontainer with common dependencies of most Ruby projects

### Fixed

- token replacement of {TARGET|GEM|NAME}

## [1.1.58] - 2025-11-13

- TAG: [v1.1.58][1.1.58t]
- COVERAGE: 94.41% -- 4067/4308 lines in 26 files
- BRANCH COVERAGE: 78.77% -- 1673/2124 branches in 26 files
- 79.89% documented

### Added

- Ignore more .idea plugin artifacts

### Fixed

- bin/rake yard no longer overrides the .yardignore for checksums

## [1.1.57] - 2025-11-13

- TAG: [v1.1.57][1.1.57t]
- COVERAGE: 94.36% -- 4065/4308 lines in 26 files
- BRANCH COVERAGE: 78.81% -- 1674/2124 branches in 26 files
- 79.89% documented

### Added

- New Rake task: `appraisal:reset` — deletes all Appraisal lockfiles (`gemfiles/*.gemfile.lock`).
- Improved .env.local.example template

### Fixed

- .yardignore more comprehensively ignores directories that are not relevant to documentation

## [1.1.56] - 2025-11-11

- TAG: [v1.1.56][1.1.56t]
- COVERAGE: 94.38% -- 4066/4308 lines in 26 files
- BRANCH COVERAGE: 78.77% -- 1673/2124 branches in 26 files
- 79.89% documented

### Fixed

- Appraisals template merge with existing header
- Don't set opencollective in FUNDING.yml when osc is disabled
- handling of open source collective ENV variables in .envrc templates
- Don't invent an open collective handle when open collective is not enabled

## [1.1.55] - 2025-11-11

- TAG: [v1.1.55][1.1.55t]
- COVERAGE: 94.41% -- 4039/4278 lines in 26 files
- BRANCH COVERAGE: 78.88% -- 1662/2107 branches in 26 files
- 79.89% documented

### Added

- GitLab Pipelines for Ruby 2.7, 3.0, 3.0

## [1.1.54] - 2025-11-11

- TAG: [v1.1.54][1.1.54t]
- COVERAGE: 94.39% -- 4038/4278 lines in 26 files
- BRANCH COVERAGE: 78.88% -- 1662/2107 branches in 26 files
- 79.89% documented

### Added

- .idea/.gitignore is now part of template

## [1.1.53] - 2025-11-10

- TAG: [v1.1.53][1.1.53t]
- COVERAGE: 94.41% -- 4039/4278 lines in 26 files
- BRANCH COVERAGE: 78.93% -- 1663/2107 branches in 26 files
- 79.89% documented

### Added

- Template .yardopts now includes yard-yaml plugin (for CITATION.cff)
- Template now includes a default `.yardopts` file
  - Excludes *.gem, pkg/*.gem and .yardoc from documentation generation

## [1.1.52] - 2025-11-08

- TAG: [v1.1.52][1.1.52t]
- COVERAGE: 94.37% -- 4037/4278 lines in 26 files
- BRANCH COVERAGE: 78.93% -- 1663/2107 branches in 26 files
- 79.89% documented

### Added

- Update documentation

### Changed

- Upgrade to yard-fence v0.8.0

## [1.1.51] - 2025-11-07

- TAG: [v1.1.51][1.1.51t]
- COVERAGE: 94.41% -- 4039/4278 lines in 26 files
- BRANCH COVERAGE: 78.88% -- 1662/2107 branches in 26 files
- 79.89% documented

### Removed

- unused file removed from template
  - functionality was replaced by yard-fence gem

## [1.1.50] - 2025-11-07

- TAG: [v1.1.50][1.1.50t]
- COVERAGE: 94.41% -- 4039/4278 lines in 26 files
- BRANCH COVERAGE: 78.88% -- 1662/2107 branches in 26 files
- 79.89% documented

### Fixed

- invalid documentation (bad find/replace outcomes during templating)

## [1.1.49] - 2025-11-07

- TAG: [v1.1.49][1.1.49t]
- COVERAGE: 94.39% -- 4038/4278 lines in 26 files
- BRANCH COVERAGE: 78.93% -- 1663/2107 branches in 26 files
- 79.89% documented

### Added

- yard-fence for handling braces in fenced code blocks in yard docs
- Improved documentation

## [1.1.48] - 2025-11-06

- TAG: [v1.1.48][1.1.48t]
- COVERAGE: 94.39% -- 4038/4278 lines in 26 files
- BRANCH COVERAGE: 78.93% -- 1663/2107 branches in 26 files
- 79.89% documented

### Fixed

- Typo in markdown link
- Handling of pre-existing gemfile

## [1.1.47] - 2025-11-06

- TAG: [v1.1.47][1.1.47t]
- COVERAGE: 95.68% -- 4054/4237 lines in 26 files
- BRANCH COVERAGE: 80.45% -- 1675/2082 branches in 26 files
- 79.89% documented

### Added

- Handle custom dependencies in Gemfiles gracefully
- Intelligent templating of Appraisals

### Fixed

- Typos in funding links

## [1.1.46] - 2025-11-04

- TAG: [v1.1.46][1.1.46t]
- COVERAGE: 96.25% -- 3958/4112 lines in 26 files
- BRANCH COVERAGE: 80.95% -- 1636/2021 branches in 26 files
- 79.68% documented

### Added

- Validate RBS Types within style workflow

### Fixed

- typos in README.md

## [1.1.45] - 2025-10-31

- TAG: [v1.1.45][1.1.45t]
- COVERAGE: 96.33% -- 3961/4112 lines in 26 files
- BRANCH COVERAGE: 81.00% -- 1637/2021 branches in 26 files
- 79.68% documented

### Changed

- floss-funding related documentation improvements

## [1.1.44] - 2025-10-31

- TAG: [v1.1.44][1.1.44t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Removed

- `exe/*` from `spec.files`, because it is redundant with `spec.bindir` & `spec.executables`
- prepare-commit-msg.example: no longer needed

### Fixed

- prepare-commit-msg git hook: incompatibility between direnv and mise by removing `direnv exec`

## [1.1.43] - 2025-10-30

- TAG: [v1.1.43][1.1.43t]
- COVERAGE: 96.06% -- 3950/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Fixed

- typos in CONTRIBUTING.md used for templating

## [1.1.42] - 2025-10-29

- TAG: [v1.1.42][1.1.42t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Removed

- Exclude `gemfiles/modular/injected.gemfile` from the install/template process, as it is not relevant.

## [1.1.41] - 2025-10-28

- TAG: [v1.1.41][1.1.41t]
- COVERAGE: 96.06% -- 3950/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Changed

- Improved formatting of errors

## [1.1.40] - 2025-10-28

- TAG: [v1.1.40][1.1.40t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Changed

- Improved copy for this gem and templated gems

## [1.1.39] - 2025-10-27

- TAG: [v1.1.39][1.1.39t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Added

- CONTRIBUTING.md.example tailored for the templated gem

### Fixed

- Minor typos

## [1.1.38] - 2025-10-21

- TAG: [v1.1.38][1.1.38t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.80% -- 1633/2021 branches in 26 files
- 79.68% documented

### Changed

- legacy ruby 3.1 pinned to bundler 2.6.9

### Fixed

- Corrected typo: truffleruby-24.1 (targets Ruby 3.3 compatibility)

## [1.1.37] - 2025-10-21

- TAG: [v1.1.37][1.1.37t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.80% -- 1633/2021 branches in 26 files
- 79.68% documented

### Added

- kettle-release: improved --help
- improved documentation of kettle-release
- improved documentation of spec setup with kettle-test

### Changed

- upgrade to kettle-test v1.0.6

## [1.1.36] - 2025-10-20

- TAG: [v1.1.36][1.1.36t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Added

- More documentation of RC situation

### Fixed

- alphabetize dependencies

## [1.1.35] - 2025-10-20

- TAG: [v1.1.35][1.1.35t]
- COVERAGE: 96.04% -- 3949/4112 lines in 26 files
- BRANCH COVERAGE: 80.85% -- 1634/2021 branches in 26 files
- 79.68% documented

### Added

- more documentation of the RC.O situation

### Changed

- upgraded kettle-test to v1.0.5

### Removed

- direct dependency on rspec-pending_for (now provided, and configured, by kettle-test)

## [1.1.34] - 2025-10-20

- TAG: [v1.1.34][1.1.34t]
- COVERAGE: 96.10% -- 3938/4098 lines in 26 files
- BRANCH COVERAGE: 80.92% -- 1624/2007 branches in 26 files
- 79.68% documented

### Changed

- kettle-release: Make step 17 only push the checksum commit; bin/gem_checksums creates the commit internally.
- kettle-release: Ensure a final push of tags occurs after checksums and optional GitHub release; supports an 'all' remote aggregator when configured.

### Fixed

- fixed rake task compatibility with BUNDLE_PATH (i.e. vendored bundle)
  - appraisal tasks
  - bench tasks
  - reek tasks

## [1.1.33] - 2025-10-13

- TAG: [v1.1.33][1.1.33t]
- COVERAGE: 20.83% -- 245/1176 lines in 9 files
- BRANCH COVERAGE: 7.31% -- 43/588 branches in 9 files
- 79.57% documented

### Added

- handling for no open source collective, specified by:
  - `ENV["FUNDING_ORG"]` set to "false", or
  - `ENV["OPENCOLLECTIVE_HANDLE"]` set to "false"
- added codeberg gem source

### Changed

- removed redundant github gem source

### Fixed

- added addressable to optional modular gemfile template, as it is required for kettle-pre-release
- handling of env.ACT conditions in workflows

## [1.1.32] - 2025-10-07

- TAG: [v1.1.32][1.1.32t]
- COVERAGE: 96.39% -- 3929/4076 lines in 26 files
- BRANCH COVERAGE: 81.07% -- 1619/1997 branches in 26 files
- 79.12% documented

### Added

- A top-level note on gem server switch in README.md & template

### Changed

- Switch to cooperative gem server
  - https://gem.coop

## [1.1.31] - 2025-09-21

- TAG: [v1.1.31][1.1.31t]
- COVERAGE: 96.39% -- 3929/4076 lines in 26 files
- BRANCH COVERAGE: 81.07% -- 1619/1997 branches in 26 files
- 79.12% documented

### Fixed

- order of checksums and release / tag reversed
  - remove all possibility of gem rebuild (part of reproducible builds) including checksums in the rebuilt gem

## [1.1.30] - 2025-09-21

- TAG: [v1.1.30][1.1.30t]
- COVERAGE: 96.27% -- 3926/4078 lines in 26 files
- BRANCH COVERAGE: 80.97% -- 1617/1997 branches in 26 files
- 79.12% documented

### Added

- kettle-changelog: handle legacy tag-in-release-heading style
  - convert to tag-in-list style

## [1.1.29] - 2025-09-21

- TAG: [v1.1.29][1.1.29t]
- COVERAGE: 96.19% -- 3861/4014 lines in 26 files
- BRANCH COVERAGE: 80.74% -- 1589/1968 branches in 26 files
- 79.12% documented

### Changed

- Testing release

## [1.1.28] - 2025-09-21

- TAG: [v1.1.28][1.1.28t]
- COVERAGE: 96.19% -- 3861/4014 lines in 26 files
- BRANCH COVERAGE: 80.89% -- 1592/1968 branches in 26 files
- 79.12% documented

### Fixed

- kettle-release: restore compatability with MFA input

## [1.1.27] - 2025-09-20

- TAG: [v1.1.27][1.1.27t]
- COVERAGE: 96.33% -- 3860/4007 lines in 26 files
- BRANCH COVERAGE: 81.09% -- 1591/1962 branches in 26 files
- 79.12% documented

### Changed

- Use obfuscated URLs, and avatars from Open Collective in ReadmeBackers

### Fixed

- improved handling of flaky truffleruby builds in workflow templates
- fixed handling of kettle-release when checksums are present and unchanged causing the gem_checksums script to fail

## [1.1.25] - 2025-09-18

- TAG: [v1.1.25][1.1.25t]
- COVERAGE: 96.87% -- 3708/3828 lines in 26 files
- BRANCH COVERAGE: 81.69% -- 1526/1868 branches in 26 files
- 78.33% documented

### Fixed

- kettle-readme-backers fails gracefully when README_UPDATER_TOKEN is missing from org secrets

## [1.1.24] - 2025-09-17

- TAG: [v1.1.24][1.1.24t]
- COVERAGE: 96.85% -- 3694/3814 lines in 26 files
- BRANCH COVERAGE: 81.81% -- 1520/1858 branches in 26 files
- 78.21% documented

### Added

- Replace template tokens with real minimum ruby versions for runtime and development

### Changed

- consolidated specs

### Fixed

- All .example files are now included in the gem package
- Leaky state in specs

## [1.1.23] - 2025-09-16

- TAG: [v1.1.23][1.1.23t]
- COVERAGE: 96.71% -- 3673/3798 lines in 26 files
- BRANCH COVERAGE: 81.57% -- 1509/1850 branches in 26 files
- 77.97% documented

### Fixed

- GemSpecReader, ReadmeBackers now use shared OpenCollectiveConfig
  - fixes broken opencollective config handling in GemSPecReader

## [1.1.22] - 2025-09-16

- TAG: [v1.1.22][1.1.22t]
- COVERAGE: 96.83% -- 3661/3781 lines in 25 files
- BRANCH COVERAGE: 81.70% -- 1505/1842 branches in 25 files
- 77.01% documented

### Changed

- Revert "🔒️ Use pull_request_target in workflows"
  - It's not relevant to my projects (either this gem or the ones templated)

## [1.1.21] - 2025-09-16

- TAG: [v1.1.21][1.1.21t]
- COVERAGE: 96.83% -- 3661/3781 lines in 25 files
- BRANCH COVERAGE: 81.65% -- 1504/1842 branches in 25 files
- 77.01% documented

### Changed

- improved templating
- improved documentation

### Fixed

- kettle-readme-backers: read correct config file
  - .opencollective.yml in project root

## [1.1.20] - 2025-09-15

- TAG: [v1.1.20][1.1.20t]
- COVERAGE: 96.80% -- 3660/3781 lines in 25 files
- BRANCH COVERAGE: 81.65% -- 1504/1842 branches in 25 files
- 77.01% documented

### Added

- Allow reformating of CHANGELOG.md without version bump
- `--include=GLOB` includes files not otherwise included in default template
- more test coverage

### Fixed

- Add .licenserc.yaml to gem package
- Handling of GFM fenced code blocks in CHANGELOG.md
- Handling of nested list items in CHANGELOG.md
- Handling of blank lines around all headings in CHANGELOG.md

## [1.1.19] - 2025-09-14

- TAG: [v1.1.19][1.1.19t]
- COVERAGE: 96.58% -- 3531/3656 lines in 25 files
- BRANCH COVERAGE: 81.11% -- 1443/1779 branches in 25 files
- 76.88% documented

### Added

- documentation of vcr on Ruby 2.4
- Apache SkyWalking Eyes dependency license check
  - Added to template

### Fixed

- fix duplicate headings in CHANGELOG.md Unreleased section

## [1.1.18] - 2025-09-12

- TAG: [v1.1.18][1.1.18t]
- COVERAGE: 96.24% -- 3477/3613 lines in 25 files
- BRANCH COVERAGE: 81.01% -- 1425/1759 branches in 25 files
- 76.88% documented

### Removed

- remove patreon link from README template

## [1.1.17] - 2025-09-11

- TAG: [v1.1.17][1.1.17t]
- COVERAGE: 96.29% -- 3479/3613 lines in 25 files
- BRANCH COVERAGE: 81.01% -- 1425/1759 branches in 25 files
- 76.88% documented

### Added

- improved documentation
- better organized readme
- badges are more clear & new badge for Ruby Friends Squad on Daily.dev
    - https://app.daily.dev/squads/rubyfriends

### Changed

- update template to version_gem v1.1.9
- right-size funding commit message append width

### Removed

- remove patreon link from README

## [1.1.16] - 2025-09-10

- TAG: [v1.1.16][1.1.16t]
- COVERAGE: 96.24% -- 3477/3613 lines in 25 files
- BRANCH COVERAGE: 81.01% -- 1425/1759 branches in 25 files
- 76.88% documented

### Fixed

- handling of alternate format of Unreleased section in CHANGELOG.md

## [1.1.15] - 2025-09-10

- TAG: [v1.1.15][1.1.15t]
- COVERAGE: 96.29% -- 3479/3613 lines in 25 files
- BRANCH COVERAGE: 80.96% -- 1424/1759 branches in 25 files
- 76.88% documented

### Fixed

- fix appraisals for Ruby v2.7 to use correct x_std_libs

## [1.1.14] - 2025-09-10

- TAG: [v1.1.14][1.1.14t]
- COVERAGE: 96.24% -- 3477/3613 lines in 25 files
- BRANCH COVERAGE: 80.96% -- 1424/1759 branches in 25 files
- 76.88% documented

### Changed

- use current x_std_libs modular gemfile for all appraisals that are pinned to current ruby
- fix appraisals for Ruby v2 to use correct version of erb

## [1.1.13] - 2025-09-09

- TAG: [v1.1.13][1.1.13t]
- COVERAGE: 96.29% -- 3479/3613 lines in 25 files
- BRANCH COVERAGE: 80.96% -- 1424/1759 branches in 25 files
- 76.88% documented

### Fixed

- include .rubocop_rspec.yml during install / template task's file copy
- kettle-dev-setup now honors `--force` option

## [1.1.12] - 2025-09-09

- TAG: [v1.1.12][1.1.12t]
- COVERAGE: 94.84% -- 3422/3608 lines in 25 files
- BRANCH COVERAGE: 78.97% -- 1386/1755 branches in 25 files
- 76.88% documented

### Changed

- improve Gemfile updates during kettle-dev-setup
- git origin-based funding_org derivation during setup

## [1.1.11] - 2025-09-08

- TAG: [v1.1.11][1.1.11t]
- COVERAGE: 96.56% -- 3396/3517 lines in 24 files
- BRANCH COVERAGE: 81.33% -- 1385/1703 branches in 24 files
- 77.06% documented

### Changed

- move kettle-dev-setup logic into Kettle::Dev::SetupCLI

### Fixed

- gem dependency detection in kettle-dev-setup to prevent duplication

## [1.1.10] - 2025-09-08

- TAG: [v1.1.10][1.1.10t]
- COVERAGE: 97.14% -- 3256/3352 lines in 23 files
- BRANCH COVERAGE: 81.91% -- 1345/1642 branches in 23 files
- 76.65% documented

### Added

- Improve documentation
  - Fix an internal link in README.md

### Changed

- template task no longer overwrites CHANGELOG.md completely
  - attempts to retain existing release notes content

### Fixed

- Fix a typo in the README.md

### Fixed

- fix typo in the path to x_std_libs.gemfile

## [1.1.9] - 2025-09-07

- TAG: [v1.1.9][1.1.9t]
- COVERAGE: 97.11% -- 3255/3352 lines in 23 files
- BRANCH COVERAGE: 81.91% -- 1345/1642 branches in 23 files
- 76.65% documented

### Added

- badge for current runtime heads in example readme

### Fixed

- Add gemfiles/modular/x_std_libs.gemfile & injected.gemfile to template
- example version of gemfiles/modular/runtime_heads.gemfile
  - necessary to avoid deps on recording gems in the template

## [1.1.8] - 2025-09-07

- TAG: [v1.1.8][1.1.8t]
- COVERAGE: 97.16% -- 3246/3341 lines in 23 files
- BRANCH COVERAGE: 81.95% -- 1344/1640 branches in 23 files
- 76.97% documented

### Added

- add .aiignore to the template
- add .rubocop_rspec.yml to the template
- gemfiles/modular/x_std_libs pattern to template, including:
  - erb
  - mutex_m
  - stringio
- gemfiles/modular/debug.gemfile
- gemfiles/modular/runtime_heads.gemfile
- .github/workflows/dep-heads.yml
- (performance) filter and prioritize example files in the `.github` directory
- added codecov config to the template
- Kettle::Dev.default_registered?

### Fixed

- run specs as part of the test task

## [1.1.7] - 2025-09-06

- TAG: [v1.1.7][1.1.7t]
- COVERAGE: 97.12% -- 3237/3333 lines in 23 files
- BRANCH COVERAGE: 81.95% -- 1344/1640 branches in 23 files
- 76.97% documented

### Added

- rake task - `appraisal:install`
  - initial setup for projects that didn't previously use Appraisal

### Changed

- .git-hooks/commit-msg allows commit if gitmoji-regex is unavailable
- simplified `*Task` classes' `task_abort` methods to just raise Kettle::Dev::Error
  - Allows caller to decide how to handle.

### Removed

- addressable, rake runtime dependencies
  - moved to optional, or development dependencies

### Fixed

- Fix local CI via act for templated workflows (skip JRuby in nektos/act locally)

## [1.1.6] - 2025-09-05

- TAG: [v1.1.6][1.1.6t]
- COVERAGE: 97.06% -- 3241/3339 lines in 23 files
- BRANCH COVERAGE: 81.83% -- 1347/1646 branches in 23 files
- 76.97% documented

### Fixed

- bin/rake test works for minitest

## [1.1.5] - 2025-09-04

- TAG: [v1.1.5][1.1.5t]
- COVERAGE: 33.87% -- 1125/3322 lines in 22 files
- BRANCH COVERAGE: 22.04% -- 361/1638 branches in 22 files
- 76.83% documented

### Added

- kettle-pre-release: run re-release checks on a library
  - validate URLs of image assets in Markdown files
- honor ENV["FUNDING_FORGE"] set to "false" as intentional disabling of funding-related logic.
- Add CLI Option --only passthrough from kettle-dev-setup to Installation Task
- Comprehensive documentation of all exe/ scripts in README.md
- add gitlab pipeline result to ci:act
- highlight SHA discrepancies in ci:act task header info
- how to set up forge tokens for ci:act, and other tools, instructions for README.md

### Changed

- expanded use of adapter patterns (Exit, Git, and Input)
- refactored and improved structure of code, more resilient
- kettle-release: do not abort immediately on CI failure; continue checking all workflows, summarize results, and prompt to (c)ontinue or (q)uit (reuses ci:act-style summary)

### Removed

- defensive NameError handling in ChangelogCLI.abort method

### Fixed

- replace token `{OPENCOLLECTIVE|ORG_NAME}` with funding org name
- prefer .example version of .git-hooks
- kettle-commit-msg now runs via rubygems (not bundler) so it will work via a system gem
- fixed logic for handling derivation of forge and funding URLs
- allow commits to succeed if dependencies are missing or broken
- RBS types documentation for GemSpecReader

## [1.1.4] - 2025-09-02

- TAG: [v1.1.4][1.1.4t]
- COVERAGE: 67.64% -- 554/819 lines in 9 files
- BRANCH COVERAGE: 53.25% -- 221/415 branches in 9 files
- 76.22% documented

### Fixed

- documentation of rake tasks from this gem no longer includes standard gem tasks
- kettle-dev-setup: package bin/setup so setup can copy it
- kettle_dev_install task: set executable flag for .git-hooks script when installing

## [1.1.3] - 2025-09-02

- TAG: [v1.1.3][1.1.3t]
- COVERAGE: 97.14% -- 2857/2941 lines in 22 files
- BRANCH COVERAGE: 82.29% -- 1194/1451 branches in 22 files
- 76.22% documented

### Changed

- URL for migrating repo to CodeBerg:
  - https://codeberg.org/repo/migrate

### Fixed

- Stop double defining DEBUGGING constant

## [1.1.2] - 2025-09-02

- TAG: [v1.1.2][1.1.2t]
- COVERAGE: 97.14% -- 2858/2942 lines in 22 files
- BRANCH COVERAGE: 82.29% -- 1194/1451 branches in 22 files
- 76.76% documented

### Added

- .gitlab-ci.yml documentation (in example)
- kettle-dvcs script for setting up DVCS, and checking status of remotes
  - https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
- kettle-dvcs --status: prefix "ahead by N" with ✅️ when N==0, and 🔴 when N>0
- kettle-dvcs --status: also prints a Local status section comparing local HEAD to origin/<branch>, and keeps origin visible via that section
- Document kettle-dvcs CLI in README (usage, options, examples)
- RBS types for Kettle::Dev::DvcsCLI and inline YARD docs on CLI
- Specs for DvcsCLI covering remote normalization, fetch outcomes, and README updates

### Changed

- major spec refactoring

### Fixed

- (linting) rspec-pending_for 0.0.17+ (example gemspec)

## [1.1.1] - 2025-09-02

- TAG: [v1.1.1][1.1.1t]
- COVERAGE: 97.04% -- 2655/2736 lines in 21 files
- BRANCH COVERAGE: 82.21% -- 1109/1349 branches in 21 files
- 76.81% documented

### Added

- .simplecov.example - keeps it generic
- improved documentation on automatic release script
- .gitlab-ci.yml documentation

### Fixed

- reduce extra leading whitespace in info table column 2

## [1.1.0] - 2025-09-02

- TAG: [v1.1.0][1.1.0t]
- COVERAGE: 97.03% -- 2649/2730 lines in 21 files
- BRANCH COVERAGE: 82.16% -- 1105/1345 branches in 21 files
- 76.81% documented

### Added

- exe/kettle-dev-setup - bootstrap templating in any RubyGem

### Removed

- all runtime deps
  - dependencies haven't really changed; will be injected into the gemspec of the including gem
  - **almost** a breaking change; but this gem re-templates other gems
  - so non-breaking via re-templating.

## [1.0.27] - 2025-09-01

- TAG: [v1.0.27][1.0.27t]
- COVERAGE: 97.77% -- 2629/2689 lines in 22 files
- BRANCH COVERAGE: 82.40% -- 1100/1335 branches in 22 files
- 76.47% documented

### Changed

- Use semver version dependency (~> 1.0) on kettle-dev when templating

### Removed

- dependency on version_gem (backwards compatible change)

## [1.0.26] - 2025-09-01

- TAG: [v1.0.26][1.0.26t]
- COVERAGE: 97.81% -- 2630/2689 lines in 22 files
- BRANCH COVERAGE: 82.40% -- 1100/1335 branches in 22 files
- 75.00% documented

### Fixed

- .env.local.example is now included in the packaged gem
  - making the copy by install / template tasks possible

## [1.0.25] - 2025-08-31

- TAG: [v1.0.25][1.0.25t]
- COVERAGE: 97.81% -- 2630/2689 lines in 22 files
- BRANCH COVERAGE: 82.40% -- 1100/1335 branches in 22 files
- 75.00% documented

### Added

- test that .env.local.example is copied by install / template tasks

### Changed

- update Appraisals.example template's instructions for updating appraisals

## [1.0.24] - 2025-08-31

- TAG: [v1.0.24][1.0.24t]
- COVERAGE: 97.51% -- 2625/2692 lines in 22 files
- BRANCH COVERAGE: 81.97% -- 1096/1337 branches in 22 files
- 75.00% documented

### Added

- improved documentation
- more badges in README (gem & template)
- integration test for kettle-changelog using CHANGELOG.md.
- integration test for kettle-changelog using KEEP_A_CHANGELOG.md.

### Changed

- add output to error handling related to release creation on GitHub
- refactored Kettle::Dev::Tasks::CITask.abort => task_abort
  - Avoids method name clash with ExitAdapter
  - follows the pattern of other Kettle::Dev::Tasks modules
- move --help handling for kettle-changelog to kettle-changelog itself

### Fixed

- typos in README for gem & template
- kettle-changelog: more robust in retention of version chunks, and markdown link refs, that are not relevant to the chunk being added
- rearrange footer links in changelog by order, newest first, oldest last
- `Kettle::Dev::Tasks::CITask.act` returns properly when running non-interactively
- replace Underscores with Dashes in Gem Names for [🚎yard-head] link

## [1.0.23] - 2025-08-30

- TAG: [v1.0.23][1.0.23t]
- COVERAGE: 97.75% -- 2428/2484 lines in 21 files
- BRANCH COVERAGE: 81.76% -- 1013/1239 branches in 21 files
- 76.00% documented

### Added

- Carryover important fields from the original gemspec during templating
  - refactor gemspec parsing
  - normalize template gemspec data

### Fixed

- include FUNDING.md in the released gem package
- typo of required_ruby_version

## [1.0.22] - 2025-08-30

- TAG: [v1.0.22][1.0.22t]
- COVERAGE: 97.82% -- 2375/2428 lines in 20 files
- BRANCH COVERAGE: 81.34% -- 972/1195 branches in 20 files
- 76.23% documented

### Added

- improved documentation
- example version of heads workflow
  - give heads two attempts to succeed

## [1.0.21] - 2025-08-30

- TAG: [v1.0.21][1.0.21t]
- COVERAGE: 97.82% -- 2375/2428 lines in 20 files
- BRANCH COVERAGE: 81.34% -- 972/1195 branches in 20 files
- 76.23% documented

### Added

- FUNDING.md in support of a funding footer on release notes
  - <!-- RELEASE-NOTES-FOOTER-START -->
  - <!-- RELEASE-NOTES-FOOTER-END -->
- truffle workflow: Repeat attempts for bundle install and appraisal bundle before failure
- global token replacement during kettle:dev:install
  - kettle-dev => kettle-dev
  - {RUBOCOP|LTS|CONSTRAINT} => dynamic
  - {RUBOCOP|RUBY|GEM} => dynamic
  - default to rubocop-ruby1_8 if no minimum ruby specified
- template supports local development of RuboCop-LTS suite of gems
- improved documentation

### Changed

- dependabot: ignore rubocop-lts for updates
- template configures RSpec to run tests in random order

## [1.0.20] - 2025-08-29

- TAG: [v1.0.20][1.0.20t]
- COVERAGE: 14.01% -- 96/685 lines in 8 files
- BRANCH COVERAGE: 0.30% -- 1/338 branches in 8 files
- 76.23% documented

### Changed

- Use example version of ancient.yml workflow since local version has been customized
- Use example version of jruby.yml workflow since local version has been customized

## [1.0.19] - 2025-08-29

- TAG: [v1.0.19][1.0.19t]
- COVERAGE: 97.84% -- 2350/2402 lines in 20 files
- BRANCH COVERAGE: 81.46% -- 962/1181 branches in 20 files
- 76.23% documented

### Fixed

- replacement logic handles a dashed gem-name which maps onto a nested path structure

## [1.0.18] - 2025-08-29

- TAG: [v1.0.18][1.0.18t]
- COVERAGE: 71.70% -- 456/636 lines in 9 files
- BRANCH COVERAGE: 51.17% -- 153/299 branches in 9 files
- 76.23% documented

### Added

- kettle:dev:install can overwrite gemspec with example gemspec
- documentation for the start_step CLI option for kettle-release
- kettle:dev:install and kettle:dev:template support `only=` option with glob filtering:
  - comma-separated glob patterns matched against destination paths relative to project root
  - non-matching files are excluded from templating.

### Fixed

- kettle:dev:install remove "Works with MRI Ruby*" lines with no badges left
- kettle:dev:install prefix badge cell replacement with a single space

## [1.0.17] - 2025-08-29

- TAG: [v1.0.17][1.0.17t]
- COVERAGE: 98.14% -- 2271/2314 lines in 20 files
- BRANCH COVERAGE: 81.42% -- 916/1125 branches in 20 files
- 76.23% documented

### Fixed

- kettle-changelog added to exe files so packaged with released gem

## [1.0.16] - 2025-08-29

- TAG: [v1.0.16][1.0.16t]
- COVERAGE: 98.14% -- 2271/2314 lines in 20 files
- BRANCH COVERAGE: 81.42% -- 916/1125 branches in 20 files
- 76.23% documented

### Fixed

- default rake task must be defined before it can be enhanced

## [1.0.15] - 2025-08-29

- TAG: [v1.0.15][1.0.15t]
- COVERAGE: 98.17% -- 2259/2301 lines in 20 files
- BRANCH COVERAGE: 81.00% -- 908/1121 branches in 20 files
- 76.03% documented

### Added

- kettle-release: early validation of identical set of copyright years in README.md and CHANGELOG.md, adds current year if missing, aborts on mismatch
- kettle-release: update KLOC in README.md
- kettle-release: update Rakefile.example with version and date

### Changed

- kettle-release: print package name and version released as final line
- use git adapter to wrap more git commands to make tests easier to build
- stop testing Ruby 2.4 on CI due to a strange issue with VCR.
  - still testing Ruby 2.3

### Fixed

- include gemfiles/modular/*gemfile.example with packaged gem
- CI workflow result polling logic revised:
  - includes a delay
  - scopes queries to specific commit SHA
  - prevents false failures from previous runs

## [1.0.14] - 2025-08-28

- TAG: [v1.0.14][1.0.14t]
- COVERAGE: 97.70% -- 2125/2175 lines in 20 files
- BRANCH COVERAGE: 78.77% -- 842/1069 branches in 20 files
- 76.03% documented

### Added

- kettle-release: Push tags to additional remotes after release

### Changed

- Improve .gitlab-ci.yml pipeline

### Fixed

- Removed README badges for unsupported old Ruby versions
- Minor inconsistencies in template files
- git added as a dependency to optional.gemfile instead of the example template

## [1.0.13] - 2025-08-28

- TAG: [v1.0.13][1.0.13t]
- COVERAGE: 41.94% -- 65/155 lines in 6 files
- BRANCH COVERAGE: 1.92% -- 1/52 branches in 6 files
- 76.03% documented

### Added

- kettle-release: Create GitHub release from tag & changelog entry

## [1.0.12] - 2025-08-28

- TAG: [v1.0.12][1.0.12t]
- COVERAGE: 97.80% -- 1957/2001 lines in 19 files
- BRANCH COVERAGE: 79.98% -- 763/954 branches in 19 files
- 78.70% documented

### Added

- CIMonitor to consolidate workflow / pipeline monitoring logic for GH/GL across kettle-release and rake tasks, with handling for:
  - minutes exhausted
  - blocked
  - not configured
  - normal failures
  - pending
  - queued
  - running
  - success
- Ability to restart kettle-release from any failed step, so manual fixed can be applied.
  - Example (after intermittent failure of CI): `bundle exec kettle-release start_step=10`

### Fixed

- added optional.gemfile.example, and handling for it in templating
- kettle-changelog: ensure a blank line at end of file
- add sleep(0.2) to ci:act to prevent race condition with stdout flushing
- kettle-release: ensure SKIP_GEM_SIGNING works as expected with values of "true" or "false"
  - ensure it doesn't abort the process in CI

## [1.0.11] - 2025-08-28

- TAG: [v1.0.11][1.0.11t]
- COVERAGE: 97.90% -- 1959/2001 lines in 19 files
- BRANCH COVERAGE: 79.98% -- 763/954 branches in 19 files
- 78.70% documented

### Added

- Add more .example templates
    - .github/workflows/coverage.yml.example
    - .gitlab-ci.yml.example
    - Appraisals.example
- Kettle::Dev::InputAdapter: Input indirection layer for safe interactive prompts in tests; provides gets and readline; documented with YARD and typed with RBS.
- install task README improvements
    - extracts emoji grapheme from H1 to apply to gemspec's summary and description
    - removes badges for unsupported rubies, and major version MRI row if all badges removed
- new exe script: kettle-changelog - transitions a changelog from unreleased to next release

### Changed

- Make 'git' gem dependency optional; fall back to raw `git` commands when the gem is not present (rescues LoadError). See Kettle::Dev::GitAdapter.
- upgraded to stone_checksums v1.0.2
- exe scripts now print their name and version as they start up

### Removed

- dependency on git gem
    - git gem is still supported if present and not bypassed by new ENV variable `KETTLE_DEV_DISABLE_GIT_GEM`
    - no longer a direct dependency

### Fixed

- Upgrade stone_checksums for release compatibility with bundler v2.7+
    - Retains compatibility with older bundler < v2.7
- Ship all example templates with gem
- install task README preservation
    - preserves H1 line, and specific H2 headed sections
    - preserve table alignment

## [1.0.10] - 2025-08-24

- TAG: [v1.0.10][1.0.10t]
- COVERAGE: 97.68% -- 1685/1725 lines in 17 files
- BRANCH COVERAGE: 77.54% -- 618/797 branches in 17 files
- 95.35% documented

### Added

- runs git add --all before git commit, to ensure all files are committed.

### Changed

- This gem is now loaded via Ruby's standard `autoload` feature.
- Bundler is always expected, and most things probably won't work without it.
- exe/ scripts and rake tasks logic is all now moved into classes for testability, and is nearly fully covered by tests.
- New Kettle::Dev::GitAdapter class is an adapter pattern wrapper for git commands
- New Kettle::Dev::ExitAdapter class is an adapter pattern wrapper for Kernel.exit and Kernel.abort within this codebase.

### Removed

- attempts to make exe/* scripts work without bundler. Bundler is required.

### Fixed

- `Kettle::Dev::ReleaseCLI#detect_version` handles gems with multiple VERSION constants
- `kettle:dev:template` task was fixed to copy `.example` files with the destination filename lacking the `.example` extension, except for `.env.local.example`

## [1.0.9] - 2025-08-24

- TAG: [v1.0.9][1.0.9t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE:  96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Added

- kettle-release: Add a sanity check for the latest released version of the gem being released, and display it during the confirmation with user that CHANGELOG.md and version.rb have been updated, so they can compare the value in version.rb with the value of the latest released version.
    - If the value in version.rb is less than the latest released version's major or minor, then check for the latest released version that matches the major + minor of what is in version.rb.
    - This way a stable branch intended to release patch updates to older versions is able to work use the script.
- kettle-release: optional pre-push local CI run using `act`, controlled by env var `K_RELEASE_LOCAL_CI` ("true" to run, "ask" to prompt) and `K_RELEASE_LOCAL_CI_WORKFLOW` to choose a workflow; defaults to `locked_deps.yml` when present; on failure, soft-resets the release prep commit and aborts.
- template task: now copies `certs/pboling.pem` into the host project when available.

## [1.0.8] - 2025-08-24

- TAG: [v1.0.8][1.0.8t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE: 96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Fixed

- Can't add checksums to the gem package, because it changes the checksum (duh!)

## [1.0.7] - 2025-08-24

- TAG: [v1.0.7][1.0.7t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE: 96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Fixed

- Reproducible builds, with consistent checksums, by *not* using SOURCE_DATE_EPOCH.
  - Since bundler v2.7.0 builds are reproducible by default.

## [1.0.6] - 2025-08-24

- TAG: [v1.0.6][1.0.6t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE: 96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Fixed

- kettle-release: ensure SOURCE_DATE_EPOCH is applied within the same shell for both build and release by prefixing the commands with the env var (e.g., `SOURCE_DATE_EPOCH=$epoch bundle exec rake build` and `... rake release`); prevents losing the variable across shell boundaries and improves reproducible checksums.

## [1.0.5] - 2025-08-24

- TAG: [v1.0.5][1.0.5t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE: 96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Fixed

- kettle-release: will run regardless of how it is invoked (i.e. works as binstub)

## [1.0.4] - 2025-08-24

- TAG: [v1.0.4][1.0.4t]
- COVERAGE: 100.00% -- 130/130 lines in 7 files
- BRANCH COVERAGE: 96.00% -- 48/50 branches in 7 files
- 95.35% documented

### Added

- kettle-release: checks all remotes for a GitHub remote and syncs origin/trunk with it; prompts to rebase or --no-ff merge when histories diverge; pushes to both origin and the GitHub remote on merge; uses the GitHub remote for GitHub Actions CI checks, and also checks GitLab CI when a GitLab remote and .gitlab-ci.yml are present.
- kettle-release: push logic improved — if a remote named `all` exists, push the current branch to it (assumed to cover multiple push URLs). Otherwise push the current branch to `origin` and to any GitHub, GitLab, and Codeberg remotes (whatever their names are).

### Fixed

- kettle-release now validates SHA256 checksums of the built gem against the recorded checksums and aborts on mismatch; helps ensure reproducible artifacts (honoring SOURCE_DATE_EPOCH).
- kettle-release now enforces CI checks and aborts if CI cannot be verified; supports GitHub Actions and GitLab pipelines, including releases from trunk/main.
- kettle-release no longer requires bundler/setup, preventing silent exits when invoked from a dependent project; adds robust output flushing.

## [1.0.3] - 2025-08-24

- TAG: [v1.0.3][1.0.3t]
- COVERAGE: 100.00% -- 98/98 lines in 7 files
- BRANCH COVERAGE: 100.00% -- 30/30 branches in 7 files
- 94.59% documented

### Added

- template task now copies .git-hooks files necessary for git hooks to work

### Fixed

- kettle-release now uses the host project's root, instead of this gem's installed root.
- Added .git-hooks files necessary for git hooks to work

## [1.0.2] - 2025-08-24

- TAG: [v1.0.2][1.0.2t]
- COVERAGE: 100.00% -- 98/98 lines in 7 files
- BRANCH COVERAGE: 100.00% -- 30/30 branches in 7 files
- 94.59% documented

### Fixed

- Added files necessary for kettle:dev:template task to work
- .github/workflows/opencollective.yml working!

## [1.0.1] - 2025-08-24

- TAG: [v1.0.1][1.0.1t]
- COVERAGE: 100.00% -- 98/98 lines in 7 files
- BRANCH COVERAGE: 100.00% -- 30/30 branches in 7 files
- 94.59% documented

### Added

- These were documented but not yet released:
  - `kettle-release` ruby script for safely, securely, releasing a gem.
      - This may move to its own gem in the future.
  - `kettle-readme-backers` ruby script for integrating Open Source Collective backers into a README.md file.
      - This may move to its own gem in the future.

## [1.0.0] - 2025-08-24

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 100.00% -- 98/98 lines in 7 files
- BRANCH COVERAGE: 100.00% -- 30/30 branches in 7 files
- 94.59% documented

### Added

- initial release, with auto-config support for:
  - bundler-audit
  - rake
  - require_bench
  - appraisal2
  - gitmoji-regex (& git-hooks to enforce gitmoji commit-style)
  - via kettle-test
    - Note: rake tasks for kettle-test are added in *this gem* (kettle-dev) because test rake tasks are a development concern
    - rspec
      - although rspec is the focus, most tools work with minitest as well
    - rspec-block_is_expected
    - rspec-stubbed_env
    - silent_stream
    - timecop-rspec
- `kettle:dev:install` rake task for installing githooks, and various instructions for optimal configuration
- `kettle:dev:template` rake task for copying most of this gem's files (excepting bin/, docs/, exe/, sig/, lib/, specs/) to another gem, as a template.
- `ci:act` rake task CLI menu / scoreboard for a project's GHA workflows
  - Selecting will run the selected workflow via `act`
  - This may move to its own gem in the future.

[Unreleased]: https://github.com/kettle-rb/kettle-dev/compare/v1.2.5...HEAD
[1.2.5]: https://github.com/kettle-rb/kettle-dev/compare/v1.2.4...v1.2.5
[1.2.5t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.2.5
[1.2.4]: https://github.com/kettle-rb/kettle-dev/compare/v1.2.3...v1.2.4
[1.2.4t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.2.4
[1.2.3]: https://github.com/kettle-rb/kettle-dev/compare/v1.2.2...v1.2.3
[1.2.3t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.2.3
[1.2.2]: https://github.com/kettle-rb/kettle-dev/compare/v1.2.1...v1.2.2
[1.2.2t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.2.2
[1.2.0]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.60...v1.2.0
[1.2.0t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.2.0
[1.1.60]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.59...v1.1.60
[1.1.60t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.60
[1.1.59]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.58...v1.1.59
[1.1.59t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.59
[1.1.58]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.57...v1.1.58
[1.1.58t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.58
[1.1.57]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.56...v1.1.57
[1.1.57t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.57
[1.1.56]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.55...v1.1.56
[1.1.56t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.56
[1.1.55]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.54...v1.1.55
[1.1.55t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.55
[1.1.54]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.53...v1.1.54
[1.1.54t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.54
[1.1.53]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.52...v1.1.53
[1.1.53t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.53
[1.1.52]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.51...v1.1.52
[1.1.52t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.52
[1.1.51]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.50...v1.1.51
[1.1.51t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.51
[1.1.50]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.49...v1.1.50
[1.1.50t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.50
[1.1.49]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.48...v1.1.49
[1.1.49t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.49
[1.1.48]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.47...v1.1.48
[1.1.48t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.48
[1.1.47]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.46...v1.1.47
[1.1.47t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.47
[1.1.46]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.45...v1.1.46
[1.1.46t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.46
[1.1.45]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.44...v1.1.45
[1.1.45t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.45
[1.1.44]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.43...v1.1.44
[1.1.44t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.44
[1.1.43]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.42...v1.1.43
[1.1.43t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.43
[1.1.42]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.41...v1.1.42
[1.1.42t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.42
[1.1.41]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.40...v1.1.41
[1.1.41t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.41
[1.1.40]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.39...v1.1.40
[1.1.40t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.40
[1.1.39]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.38...v1.1.39
[1.1.39t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.39
[1.1.38]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.37...v1.1.38
[1.1.38t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.38
[1.1.37]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.36...v1.1.37
[1.1.37t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.37
[1.1.36]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.35...v1.1.36
[1.1.36t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.36
[1.1.35]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.34...v1.1.35
[1.1.35t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.35
[1.1.34]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.33...v1.1.34
[1.1.34t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.34
[1.1.33]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.32...v1.1.33
[1.1.33t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.33
[1.1.32]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.31...v1.1.32
[1.1.32t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.32
[1.1.31]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.30...v1.1.31
[1.1.31t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.31
[1.1.30]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.29...v1.1.30
[1.1.30t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.30
[1.1.29]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.28...v1.1.29
[1.1.29t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.29
[1.1.28]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.27...v1.1.28
[1.1.28t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.28
[1.1.27]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.25...v1.1.27
[1.1.27t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.27
[1.1.26]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.25...v1.1.26
[1.1.26t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.26
[1.1.25]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.24...v1.1.25
[1.1.25t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.25
[1.1.24]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.23...v1.1.24
[1.1.24t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.24
[1.1.23]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.22...v1.1.23
[1.1.23t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.23
[1.1.22]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.21...v1.1.22
[1.1.22t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.22
[1.1.21]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.20...v1.1.21
[1.1.21t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.21
[1.1.20]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.19...v1.1.20
[1.1.20t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.20
[1.1.19]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.18...v1.1.19
[1.1.19t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.19
[1.1.18]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.17...v1.1.18
[1.1.18t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.18
[1.1.17]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.16...v1.1.17
[1.1.17t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.17
[1.1.16]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.15...v1.1.16
[1.1.16t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.16
[1.1.15]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.14...v1.1.15
[1.1.15t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.15
[1.1.14]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.13...v1.1.14
[1.1.14t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.14
[1.1.13]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.12...v1.1.13
[1.1.13t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.13
[1.1.12]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.11...v1.1.12
[1.1.12t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.12
[1.1.11]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.10...v1.1.11
[1.1.11t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.11
[1.1.10]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.9...v1.1.10
[1.1.10t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.10
[1.1.9]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.8...v1.1.9
[1.1.9t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.9
[1.1.8]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.7...v1.1.8
[1.1.8t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.8
[1.1.7]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.6...v1.1.7
[1.1.7t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.7
[1.1.6]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.5...v1.1.6
[1.1.6t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.6
[1.1.5]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.4...v1.1.5
[1.1.5t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.5
[1.1.4]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.3...v1.1.4
[1.1.4t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.4
[1.1.3]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.2...v1.1.3
[1.1.3t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.3
[1.1.2]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.1...v1.1.2
[1.1.2t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.2
[1.1.1]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.0...v1.1.1
[1.1.1t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.1
[1.1.0]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.27...v1.1.0
[1.1.0t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.1.0
[1.0.27]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.26...v1.0.27
[1.0.27t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.27
[1.0.26]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.25...v1.0.26
[1.0.26t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.26
[1.0.25]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.24...v1.0.25
[1.0.25t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.25
[1.0.24]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.23...v1.0.24
[1.0.24t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.24
[1.0.23]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.22...v1.0.23
[1.0.23t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.23
[1.0.22]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.21...v1.0.22
[1.0.22t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.22
[1.0.21]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.20...v1.0.21
[1.0.21t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.21
[1.0.20]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.19...v1.0.20
[1.0.20t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.20
[1.0.19]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.18...v1.0.19
[1.0.19t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.19
[1.0.18]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.17...v1.0.18
[1.0.18t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.18
[1.0.17]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.16...v1.0.17
[1.0.17t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.17
[1.0.16]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.15...v1.0.16
[1.0.16t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.16
[1.0.15]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.14...v1.0.15
[1.0.15t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.15
[1.0.14]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.13...v1.0.14
[1.0.14t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.14
[1.0.13]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.12...v1.0.13
[1.0.13t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.13
[1.0.12]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.11...v1.0.12
[1.0.12t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.12
[1.0.11]: https://github.com/kettle-rb/kettle-dev/compare/v1.0.10...v1.0.11
[1.0.11t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.11
[1.0.10]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.9...v1.0.10
[1.0.10t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.10
[1.0.9]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.8...v1.0.9
[1.0.9t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.9
[1.0.8]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.7...v1.0.8
[1.0.8t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.8
[1.0.7]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.6...v1.0.7
[1.0.7t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.7
[1.0.6]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.5...v1.0.6
[1.0.6t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.6
[1.0.5]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.4...v1.0.5
[1.0.5t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.5
[1.0.4]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.3...v1.0.4
[1.0.4t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.4
[1.0.3]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.2...v1.0.3
[1.0.3t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.3
[1.0.2]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.1...v1.0.2
[1.0.2t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.2
[1.0.1]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.0...v1.0.1
[1.0.1t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.1
[1.0.0]: https://github.com/kettle-rb/kettle-dev/compare/a427c302df09cfe4253a7c8d400333f9a4c1a208...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/kettle-dev/releases/tag/v1.0.0
