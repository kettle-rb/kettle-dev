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
- Add more .example templates
  - .github/workflows/coverage.yml.example
  - .gitlab-ci.yml
### Changed
- Make 'git' gem dependency optional; fall back to raw `git` commands when the gem is not present (rescues LoadError). See Kettle::Dev::GitAdapter.
### Deprecated
### Removed
### Fixed
- Upgrade stone_checksums for release compatibility with bundler v2.7+
  - Retains compatibility with older bundler < v2.7
- Ship all example templates with gem
### Security

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

[Unreleased]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.10...HEAD
[1.0.10]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.9...v1.0.10
[1.0.10t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.10
[1.0.9]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.8...v1.0.9
[1.0.9t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.9
[1.0.8]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.7...v1.0.8
[1.0.8t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.8
[1.0.7]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.6...v1.0.7
[1.0.7t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.7
[1.0.6]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.5...v1.0.6
[1.0.6t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.6
[1.0.5]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.4...v1.0.5
[1.0.5t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.5
[1.0.4]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.3...v1.0.4
[1.0.4t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.4
[1.0.3]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.2...v1.0.3
[1.0.3t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.3
[1.0.2]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.1...v1.0.2
[1.0.2t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.2
[1.0.1]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.0...v1.0.1
[1.0.1t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.1
[1.0.0]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/a427c302df09cfe4253a7c8d400333f9a4c1a208...v1.0.0
[1.0.0t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.0
