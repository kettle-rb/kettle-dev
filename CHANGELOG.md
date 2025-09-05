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
### Changed
### Deprecated
### Removed
### Fixed
### Security

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
- replace token {OPENCOLLECTIVE|ORG_NAME} with funding org name
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
  - {KETTLE|DEV|GEM} => kettle-dev
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

## [Unreleased]
### Added
- kettle:dev:install and kettle:dev:template support `only=` option: comma-separated glob patterns matched against destination paths relative to project root; non-matching files are excluded from templating.

## [1.0.18] - 2025-08-29
- TAG: [v1.0.18][1.0.18t]
- COVERAGE: 71.70% -- 456/636 lines in 9 files
- BRANCH COVERAGE: 51.17% -- 153/299 branches in 9 files
- 76.23% documented
### Added
- kettle:dev:install can overwrite gemspec with example gemspec
- documentation for the start_step CLI option for kettle-release
- kettle:dev:install add `only=` option for glob filtering.
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
- BRANCH COVERAGE: 77.54% -- 618/797 branches in 17 files- 95.35% documented
- 77.00% documented
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

[Unreleased]: https://github.com/kettle-rb/kettle-dev/compare/v1.1.5...HEAD
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
