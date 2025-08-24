# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog v1](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning v2](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
### Changed
### Deprecated
### Removed
### Fixed
### Security

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

[Unreleased]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.1...HEAD
[1.0.1]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/v1.0.0...v1.0.1
[1.0.1t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.1
[1.0.0]: https://gitlab.com/kettle-rb/kettle-dev/-/compare/a427c302df09cfe4253a7c8d400333f9a4c1a208...v1.0.0
[1.0.0t]: https://gitlab.com/kettle-rb/kettle-dev/-/tags/v1.0.0
