# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- improved documentation by @pboling

## [2.0.13] - 2025-08-30
- TAG: [v2.0.13][2.0.13t]
- COVERAGE: 100.00% -- 519/519 lines in 14 files
- BRANCH COVERAGE: 100.00% -- 174/174 branches in 14 files
- 90.48% documented
### Added
- [gh656][gh656] - Support revocation with URL-encoded parameters
- [gh660][gh660] - Inline yard documentation by @pboling
- [gh660][gh660] - Complete RBS types documentation by @pboling
- [gh660][gh660]- (more) Comprehensive documentation / examples by @pboling
- [gh657][gh657] - Updated documentation for org-rename by @pboling
- More funding links by @Aboling0
### Changed
- Upgrade Code of Conduct to Contributor Covenant 2.1 by @pboling
- [gh660][gh660] - Shrink post-install message by 4 lines by @pboling
### Fixed
- [gh660][gh660] - Links in README (including link to HEAD documentation) by @pboling
### Security

[gh660]: https://github.com/ruby-oauth/oauth2/pull/660
[gh657]: https://github.com/ruby-oauth/oauth2/pull/657
[gh656]: https://github.com/ruby-oauth/oauth2/pull/656

## [2.0.12] - 2025-05-31
- TAG: [v2.0.12][2.0.12t]
- Line Coverage: 100.0% (520 / 520)
- Branch Coverage: 100.0% (174 / 174)
- 80.00% documented
### Added
- [gh652][gh652] - Support IETF rfc7515 JSON Web Signature - JWS by @mridang
    - Support JWT `kid` for key discovery and management
- More Documentation by @pboling
    - Documented Serialization Extensions
    - Added Gatzo.com FLOSS logo by @Aboling0, CC BY-SA 4.0
- Documentation site @ https://oauth2.galtzo.com now complete
### Changed
- Updates to gemspec (email, funding url, post install message)
### Deprecated
### Removed
### Fixed
- Documentation Typos by @pboling
### Security

[gh652]: https://github.com/oauth-xx/oauth2/pull/652
[gh652]: https://github.com/ruby-oauth/oauth2/pull/652

## [2.0.11] - 2025-05-23
- TAG: [v2.0.11][2.0.11t]
- COVERAGE: 100.00% -- 518/518 lines in 14 files
- BRANCH COVERAGE: 100.00% -- 172/172 branches in 14 files
- 80.00% documented
### Added
- [gh651](https://github.com/oauth-xx/oauth2/pull/651) - `:snaky_hash_klass` option (@pboling)
- [gh651](https://github.com/ruby-oauth/oauth2/pull/651) - `:snaky_hash_klass` option (@pboling)
- More documentation
- Codeberg as ethical mirror (@pboling)
    - https://codeberg.org/oauth-xx/oauth2
    - https://codeberg.org/ruby-oauth/oauth2
- Don't check for cert if SKIP_GEM_SIGNING is set (@pboling)
- All runtime deps, including oauth-xx sibling gems, are now tested against HEAD (@pboling)
- All runtime deps, including ruby-oauth sibling gems, are now tested against HEAD (@pboling)
- YARD config, GFM compatible with relative file links (@pboling)
- Documentation site on GitHub Pages (@pboling)
    - [oauth2.galtzo.com](https://oauth2.galtzo.com)
- [!649](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/649) - Test compatibility with all key minor versions of Hashie v0, v1, v2, v3, v4, v5, HEAD (@pboling)
- [gh651](https://github.com/oauth-xx/oauth2/pull/651) - Mock OAuth2 server for testing (@pboling)
- [!649](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/649) - Test compatibility with all key minor versions of Hashie v0, v1, v2, v3, v4, v5, HEAD (@pboling)
- [gh651](https://github.com/ruby-oauth/oauth2/pull/651) - Mock OAuth2 server for testing (@pboling)
    - https://github.com/navikt/mock-oauth2-server
### Changed
- [gh651](https://github.com/oauth-xx/oauth2/pull/651) - Upgraded to snaky_hash v2.0.3 (@pboling)
- [gh651](https://github.com/ruby-oauth/oauth2/pull/651) - Upgraded to snaky_hash v2.0.3 (@pboling)
    - Provides solution for serialization issues
- Updated `spec.homepage_uri` in gemspec to GitHub Pages YARD documentation site (@pboling)
### Fixed
- [gh650](https://github.com/oauth-xx/oauth2/pull/650) - Regression in return type of `OAuth2::Response#parsed` (@pboling)
- [gh650](https://github.com/ruby-oauth/oauth2/pull/650) - Regression in return type of `OAuth2::Response#parsed` (@pboling)
- Incorrect documentation related to silencing warnings (@pboling)

## [1.4.1] - 2018-10-13
- TAG: [v1.4.1][1.4.1t]
- [!417](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/417) - update jwt dependency (@thewoolleyman)
- [!419](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/419) - remove rubocop dependency (temporary, added back in [!423](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/423)) (@pboling)
- [!418](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/418) - update faraday dependency (@pboling)
- [!420](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/420) - update [oauth2.gemspec](https://gitlab.com/oauth-xx/oauth2/-/blob/1-4-stable/oauth2.gemspec) (@pboling)
- [!421](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/421) - fix [CHANGELOG.md](https://gitlab.com/oauth-xx/oauth2/-/blob/1-4-stable/CHANGELOG.md) for previous releases (@pboling)
- [!422](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/422) - update [LICENSE](https://gitlab.com/oauth-xx/oauth2/-/blob/1-4-stable/LICENSE) and [README.md](https://gitlab.com/oauth-xx/oauth2/-/blob/1-4-stable/README.md) (@pboling)
- [!423](https://gitlab.com/oauth-xx/oauth2/-/merge_requests/423) - update [builds](https://travis-ci.org/oauth-xx/oauth2/builds), [Rakefile](https://gitlab.com/oauth-xx/oauth2/-/blob/1-4-stable/Rakefile) (@pboling)
- [!417](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/417) - update jwt dependency (@thewoolleyman)
- [!419](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/419) - remove rubocop dependency (temporary, added back in [!423](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/423)) (@pboling)
- [!418](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/418) - update faraday dependency (@pboling)
- [!420](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/420) - update [oauth2.gemspec](https://gitlab.com/ruby-oauth/oauth2/-/blob/1-4-stable/oauth2.gemspec) (@pboling)
- [!421](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/421) - fix [CHANGELOG.md](https://gitlab.com/ruby-oauth/oauth2/-/blob/1-4-stable/CHANGELOG.md) for previous releases (@pboling)
- [!422](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/422) - update [LICENSE](https://gitlab.com/ruby-oauth/oauth2/-/blob/1-4-stable/LICENSE) and [README.md](https://gitlab.com/ruby-oauth/oauth2/-/blob/1-4-stable/README.md) (@pboling)
- [!423](https://gitlab.com/ruby-oauth/oauth2/-/merge_requests/423) - update [builds](https://travis-ci.org/ruby-oauth/oauth2/builds), [Rakefile](https://gitlab.com/ruby-oauth/oauth2/-/blob/1-4-stable/Rakefile) (@pboling)
    - officially document supported Rubies
        * Ruby 1.9.3
        * Ruby 2.0.0
        * Ruby 2.1
        * Ruby 2.2
        * [JRuby 1.7][jruby-1.7] (targets MRI v1.9)
        * [JRuby 9.0][jruby-9.0] (targets MRI v2.0)
        * Ruby 2.3
        * Ruby 2.4
        * Ruby 2.5
        * [JRuby 9.1][jruby-9.1] (targets MRI v2.3)
        * [JRuby 9.2][jruby-9.2] (targets MRI v2.5)

[jruby-1.7]: https://www.jruby.org/2017/05/11/jruby-1-7-27.html
[jruby-9.0]: https://www.jruby.org/2016/01/26/jruby-9-0-5-0.html
[jruby-9.1]: https://www.jruby.org/2017/05/16/jruby-9-1-9-0.html
[jruby-9.2]: https://www.jruby.org/2018/05/24/jruby-9-2-0-0.html

## [1.4.0] - 2017-06-09
- TAG: [v1.4.0][1.4.0t]
- Drop Ruby 1.8.7 support (@sferik)
- Fix some RuboCop offenses (@sferik)
- _Dependency_: Remove Yardstick (@sferik)
- _Dependency_: Upgrade Faraday to 0.12 (@sferik)

## [1.3.1] - 2017-03-03
- TAG: [v1.3.1][1.3.1t]
- Add support for Ruby 2.4.0 (@pschambacher)
- _Dependency_: Upgrade Faraday to Faraday 0.11 (@mcfiredrill, @rhymes, @pschambacher)

## [1.3.0] - 2016-12-28
- TAG: [v1.3.0][1.3.0t]
- Add support for header-based authentication to the `Client` so it can be used across the library (@bjeanes)
- Default to header-based authentication when getting a token from an authorisation code (@maletor)
- **Breaking**: Allow an `auth_scheme` (`:basic_auth` or `:request_body`) to be set on the client, defaulting to `:request_body` to maintain backwards compatibility (@maletor, @bjeanes)
- Handle `redirect_uri` according to the OAuth 2 spec, so it is passed on redirect and at the point of token exchange (@bjeanes)
- Refactor handling of encoding of error responses (@urkle)
- Avoid instantiating an `Error` if there is no error to raise (@urkle)
- Add support for Faraday 0.10 (@rhymes)

## [1.2.0] - 2016-07-01
- TAG: [v1.2.0][1.2.0t]
- Properly handle encoding of error responses (so we don't blow up, for example, when Google's response includes a ∞) (@Motoshi-Nishihira)
- Make a copy of the options hash in `AccessToken#from_hash` to avoid accidental mutations (@Linuus)
- Use `raise` rather than `fail` to throw exceptions (@sferik)

## [1.1.0] - 2016-01-30
- TAG: [v1.1.0][1.1.0t]
- Various refactors (eliminating `Hash#merge!` usage in `AccessToken#refresh!`, use `yield` instead of `#call`, freezing mutable objects in constants, replacing constants with class variables) (@sferik)
- Add support for Rack 2, and bump various other dependencies (@sferik)

## [1.0.0] - 2014-07-09
- TAG: [v1.0.0][1.0.0t]
### Added
- Add an implementation of the MAC token spec.
### Fixed
- Fix Base64.strict_encode64 incompatibility with Ruby 1.8.7.

## [0.5.0] - 2011-07-29
- TAG: [v0.5.0][0.5.0t]
### Changed
- *breaking* `oauth_token` renamed to `oauth_bearer`.
- *breaking* `authorize_path` Client option renamed to `authorize_url`.
- *breaking* `access_token_path` Client option renamed to `token_url`.
- *breaking* `access_token_method` Client option renamed to `token_method`.
- *breaking* `web_server` renamed to `auth_code`.

## [0.4.1] - 2011-04-20
- TAG: [v0.4.1][0.4.1t]

## [0.4.0] - 2011-04-20
- TAG: [v0.4.0][0.4.0t]

[gemfiles/readme]: gemfiles/README.md

[Unreleased]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v2.0.12...HEAD
[0.4.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v0.3.0...v0.4.0
[0.4.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v0.4.0
[0.4.1]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v0.4.0...v0.4.1
[0.4.1t]: https://github.com/ruby-oauth/oauth2/releases/tag/v0.4.1
[0.5.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v0.4.1...v0.5.0
[0.5.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v0.5.0
[1.0.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v0.9.4...v1.0.0
[1.0.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.0.0
[1.1.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v1.0.0...v1.1.0
[1.1.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.1.0
[1.2.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v1.1.0...v1.2.0
[1.2.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.2.0
[1.3.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v1.2.0...v1.3.0
[1.3.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.3.0
[1.3.1]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v1.3.0...v1.3.1
[1.3.1t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.3.1
[1.4.0]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v1.3.1...v1.4.0
[1.4.0t]: https://github.com/ruby-oauth/oauth2/releases/tag/v1.4.0
[2.0.11]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v2.0.10...v2.0.11
[2.0.11t]: https://github.com/ruby-oauth/oauth2/releases/tag/v2.0.11
[2.0.12]: https://gitlab.com/ruby-oauth/oauth2/-/compare/v2.0.11...v2.0.12
[2.0.12t]: https://github.com/ruby-oauth/oauth2/releases/tag/v2.0.12
[2.0.13]: https://github.com/ruby-oauth/oauth2/compare/v2.0.12...v2.0.13
[2.0.13t]: https://github.com/ruby-oauth/oauth2/releases/tag/v2.0.13
