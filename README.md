[![Galtzo FLOSS Logo by Aboling0, CC BY-SA 4.0][🖼️galtzo-i]][🖼️galtzo-discord] [![ruby-lang Logo, Yukihiro Matsumoto, Ruby Visual Identity Team, CC BY-SA 2.5][🖼️ruby-lang-i]][🖼️ruby-lang] [![kettle-rb Logo by Aboling0, CC BY-SA 4.0][🖼️kettle-rb-i]][🖼️kettle-rb] [![kettle-dev Logo by Aboling0, CC BY-SA 4.0][🖼️kettle-dev-i]][🖼️kettle-dev]

[🖼️galtzo-i]: https://logos.galtzo.com/assets/images/galtzo-floss/avatar-192px.svg
[🖼️galtzo-discord]: https://discord.gg/3qme4XHNKN
[🖼️ruby-lang-i]: https://logos.galtzo.com/assets/images/ruby-lang/avatar-192px.svg
[🖼️ruby-lang]: https://www.ruby-lang.org/
[🖼️kettle-rb-i]: https://logos.galtzo.com/assets/images/kettle-rb/avatar-192px.svg
[🖼️kettle-rb]: https://github.com/kettle-rb
[🖼️kettle-dev-i]: https://logos.galtzo.com/assets/images/kettle-rb/kettle-dev/avatar-192px.svg
[🖼️kettle-dev]: https://github.com/kettle-rb/kettle-dev

# 🍲 Kettle::Dev

[![Version][👽versioni]][👽version] [![GitHub tag (latest SemVer)][⛳️tag-img]][⛳️tag] [![License: AGPL-3.0-only][📄license-img]][📄license-ref] [![Downloads Rank][👽dl-ranki]][👽dl-rank] [![Open Source Helpers][👽oss-helpi]][👽oss-help] [![CodeCov Test Coverage][🏀codecovi]][🏀codecov] [![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls] [![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov] [![QLTY Maintainability][🏀qlty-mnti]][🏀qlty-mnt] [![CI Heads][🚎3-hd-wfi]][🚎3-hd-wf] [![CI Runtime Dependencies @ HEAD][🚎12-crh-wfi]][🚎12-crh-wf] [![CI Current][🚎11-c-wfi]][🚎11-c-wf] [![CI Truffle Ruby][🚎9-t-wfi]][🚎9-t-wf] [![CI JRuby][🚎10-j-wfi]][🚎10-j-wf] [![Deps Locked][🚎13-🔒️-wfi]][🚎13-🔒️-wf] [![Deps Unlocked][🚎14-🔓️-wfi]][🚎14-🔓️-wf] [![CI Test Coverage][🚎2-cov-wfi]][🚎2-cov-wf] [![CI Style][🚎5-st-wfi]][🚎5-st-wf] [![CodeQL][🖐codeQL-img]][🖐codeQL] [![Apache SkyWalking Eyes License Compatibility Check][🚎15-🪪-wfi]][🚎15-🪪-wf]

`if ci_badges.map(&:color).detect { it != "green"}` ☝️ [let me know][🖼️galtzo-discord], as I may have missed the [discord notification][🖼️galtzo-discord].

---

`if ci_badges.map(&:color).all? { it == "green"}` 👇️ send money so I can do more of this. FLOSS maintenance is now my full-time job.

[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi]

<details>
    <summary>👣 How will this project approach the September 2025 hostile takeover of RubyGems? 🚑️</summary>

I've summarized my thoughts in [this blog post](https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo).

</details>

## 🌻 Synopsis

Run the one-time project bootstrapper:

```console
kettle-dev-setup
# Or if your middle name is "danger":
# kettle-dev-setup --allowed=true --force
```

This gem integrates tightly with [kettle-test](https://github.com/kettle-rb/kettle-test).

Add this to your `spec/spec_helper.rb`:

```ruby
require "kettle/test/rspec"
```

Now you have many powerful development and testing tools at your disposal, all fully [documented](#-configuration) and tested.

If you need to top-up an old setup to get the latest goodies, just re-template:

```console
bundle exec rake kettle:dev:install
```

Making sure to review the changes, and retain overwritten bits that matter.

Later, when ready to release:

```console
bin/kettle-changelog
bin/kettle-release
```

### The `*-merge` Gem Family

The `*-merge` gem family provides intelligent, AST-based merging for various file formats. At the foundation is [tree_haver][tree_haver], which provides a unified cross-Ruby parsing API that works seamlessly across MRI, JRuby, and TruffleRuby.

| Gem                                      |                                                         Version / CI                                                         | Language<br>/ Format | Parser Backend(s)                                                                                     | Description                                                                      |
|------------------------------------------|:----------------------------------------------------------------------------------------------------------------------------:|----------------------|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| [tree_haver][tree_haver]                 |                 [![Version][tree_haver-gem-i]][tree_haver-gem] <br/> [![CI][tree_haver-ci-i]][tree_haver-ci]                 | Multi                | Supported Backends: MRI C, Rust, FFI, Java, Prism, Psych, Commonmarker, Markly, Citrus, Parslet       | **Foundation**: Cross-Ruby adapter for parsing libraries (like Faraday for HTTP) |
| [ast-merge][ast-merge]                   |                   [![Version][ast-merge-gem-i]][ast-merge-gem] <br/> [![CI][ast-merge-ci-i]][ast-merge-ci]                   | Text                 | internal                                                                                              | **Infrastructure**: Shared base classes and merge logic for all `*-merge` gems   |
| [bash-merge][bash-merge]                 |                 [![Version][bash-merge-gem-i]][bash-merge-gem] <br/> [![CI][bash-merge-ci-i]][bash-merge-ci]                 | Bash                 | [tree-sitter-bash][ts-bash] (via tree_haver)                                                          | Smart merge for Bash scripts                                                     |
| [commonmarker-merge][commonmarker-merge] | [![Version][commonmarker-merge-gem-i]][commonmarker-merge-gem] <br/> [![CI][commonmarker-merge-ci-i]][commonmarker-merge-ci] | Markdown             | [Commonmarker][commonmarker] (via tree_haver)                                                         | Smart merge for Markdown (CommonMark via comrak Rust)                            |
| [dotenv-merge][dotenv-merge]             |             [![Version][dotenv-merge-gem-i]][dotenv-merge-gem] <br/> [![CI][dotenv-merge-ci-i]][dotenv-merge-ci]             | Dotenv               | internal                                                                                              | Smart merge for `.env` files                                                     |
| [json-merge][json-merge]                 |                 [![Version][json-merge-gem-i]][json-merge-gem] <br/> [![CI][json-merge-ci-i]][json-merge-ci]                 | JSON                 | [tree-sitter-json][ts-json] (via tree_haver)                                                          | Smart merge for JSON files                                                       |
| [jsonc-merge][jsonc-merge]               |               [![Version][jsonc-merge-gem-i]][jsonc-merge-gem] <br/> [![CI][jsonc-merge-ci-i]][jsonc-merge-ci]               | JSONC                | [tree-sitter-jsonc][ts-jsonc] (via tree_haver)                                                        | ⚠️ Proof of concept; Smart merge for JSON with Comments                          |
| [markdown-merge][markdown-merge]         |         [![Version][markdown-merge-gem-i]][markdown-merge-gem] <br/> [![CI][markdown-merge-ci-i]][markdown-merge-ci]         | Markdown             | [Commonmarker][commonmarker] / [Markly][markly] (via tree_haver), [Parslet][parslet]                  | **Foundation**: Shared base for Markdown mergers with inner code block merging   |
| [markly-merge][markly-merge]             |             [![Version][markly-merge-gem-i]][markly-merge-gem] <br/> [![CI][markly-merge-ci-i]][markly-merge-ci]             | Markdown             | [Markly][markly] (via tree_haver)                                                                     | Smart merge for Markdown (CommonMark via cmark-gfm C)                            |
| [prism-merge][prism-merge]               |               [![Version][prism-merge-gem-i]][prism-merge-gem] <br/> [![CI][prism-merge-ci-i]][prism-merge-ci]               | Ruby                 | [Prism][prism] (`prism` std lib gem)                                                                  | Smart merge for Ruby source files                                                |
| [psych-merge][psych-merge]               |               [![Version][psych-merge-gem-i]][psych-merge-gem] <br/> [![CI][psych-merge-ci-i]][psych-merge-ci]               | YAML                 | [Psych][psych] (`psych` std lib gem)                                                                  | Smart merge for YAML files                                                       |
| [rbs-merge][rbs-merge]                   |                   [![Version][rbs-merge-gem-i]][rbs-merge-gem] <br/> [![CI][rbs-merge-ci-i]][rbs-merge-ci]                   | RBS                  | [tree-sitter-rbs][ts-rbs] (via tree_haver), [RBS][rbs] (`rbs` std lib gem)                            | Smart merge for Ruby type signatures                                             |
| [toml-merge][toml-merge]                 |                 [![Version][toml-merge-gem-i]][toml-merge-gem] <br/> [![CI][toml-merge-ci-i]][toml-merge-ci]                 | TOML                 | [Parslet + toml][toml], [Citrus + toml-rb][toml-rb], [tree-sitter-toml][ts-toml] (all via tree_haver) | Smart merge for TOML files                                                       |

#### Backend Platform Compatibility

tree_haver supports multiple parsing backends, but not all backends work on all Ruby platforms:

| Platform 👉️<br> TreeHaver Backend 👇️          | MRI | JRuby | TruffleRuby | Notes                                                                      |
|-------------------------------------------------|:---:|:-----:|:-----------:|----------------------------------------------------------------------------|
| **MRI** ([ruby_tree_sitter][ruby_tree_sitter])  |  ✅  |   ❌   |      ❌      | C extension, MRI only                                                      |
| **Rust** ([tree_stump][tree_stump])             |  ✅  |   ❌   |      ❌      | Rust extension via magnus/rb-sys, MRI only                                 |
| **FFI** ([ffi][ffi])                            |  ✅  |   ✅   |      ❌      | TruffleRuby's FFI doesn't support `STRUCT_BY_VALUE`                        |
| **Java** ([jtreesitter][jtreesitter])           |  ❌  |   ✅   |      ❌      | JRuby only, requires grammar JARs                                          |
| **Prism** ([prism][prism])                      |  ✅  |   ✅   |      ✅      | Ruby parsing, stdlib in Ruby 3.4+                                          |
| **Psych** ([psych][psych])                      |  ✅  |   ✅   |      ✅      | YAML parsing, stdlib                                                       |
| **Citrus** ([citrus][citrus])                   |  ✅  |   ✅   |      ✅      | Pure Ruby PEG parser, no native dependencies                               |
| **Parslet** ([parslet][parslet])                |  ✅  |   ✅   |      ✅      | Pure Ruby PEG parser, no native dependencies                               |
| **Commonmarker** ([commonmarker][commonmarker]) |  ✅  |   ❌   |      ❓      | Rust extension for Markdown (via [commonmarker-merge][commonmarker-merge]) |
| **Markly** ([markly][markly])                   |  ✅  |   ❌   |      ❓      | C extension for Markdown  (via [markly-merge][markly-merge])               |

**Legend**: ✅ = Works, ❌ = Does not work, ❓ = Untested

**Why some backends don't work on certain platforms**:

- **JRuby**: Runs on the JVM; cannot load native C/Rust extensions (`.so` files)
- **TruffleRuby**: Has C API emulation via Sulong/LLVM, but it doesn't expose all MRI internals that native extensions require (e.g., `RBasic.flags`, `rb_gc_writebarrier`)
- **FFI on TruffleRuby**: TruffleRuby's FFI implementation doesn't support returning structs by value, which tree-sitter's C API requires

**Example implementations** for the gem templating use case:

| Gem                      | Purpose         | Description                                   |
|--------------------------|-----------------|-----------------------------------------------|
| [kettle-dev][kettle-dev] | Gem Development  | Development tooling, CI automation, and release workflows |
| [kettle-jem][kettle-jem] | Gem Templating  | Gem template library with smart merge support |

[tree_haver]: https://github.com/kettle-rb/tree_haver
[ast-merge]: https://github.com/kettle-rb/ast-merge
[prism-merge]: https://github.com/kettle-rb/prism-merge
[psych-merge]: https://github.com/kettle-rb/psych-merge
[json-merge]: https://github.com/kettle-rb/json-merge
[jsonc-merge]: https://github.com/kettle-rb/jsonc-merge
[bash-merge]: https://github.com/kettle-rb/bash-merge
[rbs-merge]: https://github.com/kettle-rb/rbs-merge
[dotenv-merge]: https://github.com/kettle-rb/dotenv-merge
[toml-merge]: https://github.com/kettle-rb/toml-merge
[markdown-merge]: https://github.com/kettle-rb/markdown-merge
[markly-merge]: https://github.com/kettle-rb/markly-merge
[commonmarker-merge]: https://github.com/kettle-rb/commonmarker-merge
[kettle-dev]: https://github.com/kettle-rb/kettle-dev
[kettle-jem]: https://github.com/kettle-rb/kettle-jem
[tree_haver-gem]: https://bestgems.org/gems/tree_haver
[ast-merge-gem]: https://bestgems.org/gems/ast-merge
[prism-merge-gem]: https://bestgems.org/gems/prism-merge
[psych-merge-gem]: https://bestgems.org/gems/psych-merge
[json-merge-gem]: https://bestgems.org/gems/json-merge
[jsonc-merge-gem]: https://bestgems.org/gems/jsonc-merge
[bash-merge-gem]: https://bestgems.org/gems/bash-merge
[rbs-merge-gem]: https://bestgems.org/gems/rbs-merge
[dotenv-merge-gem]: https://bestgems.org/gems/dotenv-merge
[toml-merge-gem]: https://bestgems.org/gems/toml-merge
[markdown-merge-gem]: https://bestgems.org/gems/markdown-merge
[markly-merge-gem]: https://bestgems.org/gems/markly-merge
[commonmarker-merge-gem]: https://bestgems.org/gems/commonmarker-merge
[kettle-dev-gem]: https://bestgems.org/gems/kettle-dev
[kettle-jem-gem]: https://bestgems.org/gems/kettle-jem
[tree_haver-gem-i]: https://img.shields.io/gem/v/tree_haver.svg
[ast-merge-gem-i]: https://img.shields.io/gem/v/ast-merge.svg
[prism-merge-gem-i]: https://img.shields.io/gem/v/prism-merge.svg
[psych-merge-gem-i]: https://img.shields.io/gem/v/psych-merge.svg
[json-merge-gem-i]: https://img.shields.io/gem/v/json-merge.svg
[jsonc-merge-gem-i]: https://img.shields.io/gem/v/jsonc-merge.svg
[bash-merge-gem-i]: https://img.shields.io/gem/v/bash-merge.svg
[rbs-merge-gem-i]: https://img.shields.io/gem/v/rbs-merge.svg
[dotenv-merge-gem-i]: https://img.shields.io/gem/v/dotenv-merge.svg
[toml-merge-gem-i]: https://img.shields.io/gem/v/toml-merge.svg
[markdown-merge-gem-i]: https://img.shields.io/gem/v/markdown-merge.svg
[markly-merge-gem-i]: https://img.shields.io/gem/v/markly-merge.svg
[commonmarker-merge-gem-i]: https://img.shields.io/gem/v/commonmarker-merge.svg
[kettle-dev-gem-i]: https://img.shields.io/gem/v/kettle-dev.svg
[kettle-jem-gem-i]: https://img.shields.io/gem/v/kettle-jem.svg
[tree_haver-ci-i]: https://github.com/kettle-rb/tree_haver/actions/workflows/current.yml/badge.svg
[ast-merge-ci-i]: https://github.com/kettle-rb/ast-merge/actions/workflows/current.yml/badge.svg
[prism-merge-ci-i]: https://github.com/kettle-rb/prism-merge/actions/workflows/current.yml/badge.svg
[psych-merge-ci-i]: https://github.com/kettle-rb/psych-merge/actions/workflows/current.yml/badge.svg
[json-merge-ci-i]: https://github.com/kettle-rb/json-merge/actions/workflows/current.yml/badge.svg
[jsonc-merge-ci-i]: https://github.com/kettle-rb/jsonc-merge/actions/workflows/current.yml/badge.svg
[bash-merge-ci-i]: https://github.com/kettle-rb/bash-merge/actions/workflows/current.yml/badge.svg
[rbs-merge-ci-i]: https://github.com/kettle-rb/rbs-merge/actions/workflows/current.yml/badge.svg
[dotenv-merge-ci-i]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml/badge.svg
[toml-merge-ci-i]: https://github.com/kettle-rb/toml-merge/actions/workflows/current.yml/badge.svg
[markdown-merge-ci-i]: https://github.com/kettle-rb/markdown-merge/actions/workflows/current.yml/badge.svg
[markly-merge-ci-i]: https://github.com/kettle-rb/markly-merge/actions/workflows/current.yml/badge.svg
[commonmarker-merge-ci-i]: https://github.com/kettle-rb/commonmarker-merge/actions/workflows/current.yml/badge.svg
[kettle-dev-ci-i]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml/badge.svg
[kettle-jem-ci-i]: https://github.com/kettle-rb/kettle-jem/actions/workflows/current.yml/badge.svg
[tree_haver-ci]: https://github.com/kettle-rb/tree_haver/actions/workflows/current.yml
[ast-merge-ci]: https://github.com/kettle-rb/ast-merge/actions/workflows/current.yml
[prism-merge-ci]: https://github.com/kettle-rb/prism-merge/actions/workflows/current.yml
[psych-merge-ci]: https://github.com/kettle-rb/psych-merge/actions/workflows/current.yml
[json-merge-ci]: https://github.com/kettle-rb/json-merge/actions/workflows/current.yml
[jsonc-merge-ci]: https://github.com/kettle-rb/jsonc-merge/actions/workflows/current.yml
[bash-merge-ci]: https://github.com/kettle-rb/bash-merge/actions/workflows/current.yml
[rbs-merge-ci]: https://github.com/kettle-rb/rbs-merge/actions/workflows/current.yml
[dotenv-merge-ci]: https://github.com/kettle-rb/dotenv-merge/actions/workflows/current.yml
[toml-merge-ci]: https://github.com/kettle-rb/toml-merge/actions/workflows/current.yml
[markdown-merge-ci]: https://github.com/kettle-rb/markdown-merge/actions/workflows/current.yml
[markly-merge-ci]: https://github.com/kettle-rb/markly-merge/actions/workflows/current.yml
[commonmarker-merge-ci]: https://github.com/kettle-rb/commonmarker-merge/actions/workflows/current.yml
[kettle-dev-ci]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml
[kettle-jem-ci]: https://github.com/kettle-rb/kettle-jem/actions/workflows/current.yml
[prism]: https://github.com/ruby/prism
[psych]: https://github.com/ruby/psych
[ffi]: https://github.com/ffi/ffi
[ts-json]: https://github.com/tree-sitter/tree-sitter-json
[ts-jsonc]: https://gitlab.com/WhyNotHugo/tree-sitter-jsonc
[ts-bash]: https://github.com/tree-sitter/tree-sitter-bash
[ts-rbs]: https://github.com/joker1007/tree-sitter-rbs
[ts-toml]: https://github.com/tree-sitter-grammars/tree-sitter-toml
[dotenv]: https://github.com/bkeepers/dotenv
[rbs]: https://github.com/ruby/rbs
[toml-rb]: https://github.com/emancu/toml-rb
[toml]: https://github.com/jm/toml
[markly]: https://github.com/ioquatix/markly
[commonmarker]: https://github.com/gjtorikian/commonmarker
[ruby_tree_sitter]: https://github.com/Faveod/ruby-tree-sitter
[tree_stump]: https://github.com/joker1007/tree_stump
[jtreesitter]: https://central.sonatype.com/artifact/io.github.tree-sitter/jtreesitter
[citrus]: https://github.com/mjackson/citrus
[parslet]: https://github.com/kschiess/parslet

## 💡 Info you can shake a stick at

| Tokens to Remember      | [![Gem name][⛳️name-img]][⛳️gem-name] [![Gem namespace][⛳️namespace-img]][⛳️gem-namespace]                                                                                                                                                                                                                                                                          |
|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Works with JRuby        | [![JRuby 9.1 Compat][💎jruby-9.1i]][🚎jruby-9.1-wf] [![JRuby 9.2 Compat][💎jruby-9.2i]][🚎jruby-9.2-wf] [![JRuby 9.3 Compat][💎jruby-9.3i]][🚎jruby-9.3-wf] <br/> [![JRuby 9.4 Compat][💎jruby-9.4i]][🚎jruby-9.4-wf] [![JRuby current Compat][💎jruby-c-i]][🚎10-j-wf] [![JRuby HEAD Compat][💎jruby-headi]][🚎3-hd-wf]|
| Works with Truffle Ruby | [![Truffle Ruby 22.3 Compat][💎truby-22.3i]][🚎truby-22.3-wf] [![Truffle Ruby 23.0 Compat][💎truby-23.0i]][🚎truby-23.0-wf] [![Truffle Ruby 23.1 Compat][💎truby-23.1i]][🚎truby-23.1-wf] <br/> [![Truffle Ruby 24.2 Compat][💎truby-24.2i]][🚎truby-24.2-wf] [![Truffle Ruby 25.0 Compat][💎truby-25.0i]][🚎truby-25.0-wf] [![Truffle Ruby current Compat][💎truby-c-i]][🚎9-t-wf]|
| Works with MRI Ruby 4   | [![Ruby 4.0 Compat][💎ruby-4.0i]][🚎11-c-wf] [![Ruby current Compat][💎ruby-c-i]][🚎11-c-wf] [![Ruby HEAD Compat][💎ruby-headi]][🚎3-hd-wf]|
| Works with MRI Ruby 3   | [![Ruby 3.0 Compat][💎ruby-3.0i]][🚎ruby-3.0-wf] [![Ruby 3.1 Compat][💎ruby-3.1i]][🚎ruby-3.1-wf] [![Ruby 3.2 Compat][💎ruby-3.2i]][🚎ruby-3.2-wf] [![Ruby 3.3 Compat][💎ruby-3.3i]][🚎ruby-3.3-wf] [![Ruby 3.4 Compat][💎ruby-3.4i]][🚎ruby-3.4-wf]|
| Works with MRI Ruby 2   | [![Ruby 2.3 Compat][💎ruby-2.3i]][🚎ruby-2.3-wf] [![Ruby 2.4 Compat][💎ruby-2.4i]][🚎ruby-2.4-wf] [![Ruby 2.5 Compat][💎ruby-2.5i]][🚎ruby-2.5-wf] [![Ruby 2.6 Compat][💎ruby-2.6i]][🚎ruby-2.6-wf] [![Ruby 2.7 Compat][💎ruby-2.7i]][🚎ruby-2.7-wf]|
| Support & Community     | [![Join Me on Daily.dev's RubyFriends][✉️ruby-friends-img]][✉️ruby-friends] [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork] [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor]                                       |
| Source                  | [![Source on GitLab.com][📜src-gl-img]][📜src-gl] [![Source on CodeBerg.org][📜src-cb-img]][📜src-cb] [![Source on Github.com][📜src-gh-img]][📜src-gh] [![The best SHA: dQw4w9WgXcQ!][🧮kloc-img]][🧮kloc]                                                                                                                                                         |
| Documentation           | [![Current release on RubyDoc.info][📜docs-cr-rd-img]][🚎yard-current] [![YARD on Galtzo.com][📜docs-head-rd-img]][🚎yard-head] [![Maintainer Blog][🚂maint-blog-img]][🚂maint-blog] [![GitLab Wiki][📜gl-wiki-img]][📜gl-wiki] [![GitHub Wiki][📜gh-wiki-img]][📜gh-wiki]                                                                                          |
| Compliance              | [![License: AGPL-3.0-only][📄license-img]][📄license-ref] [![Apache license compatibility: Category X][📄license-compat-img]][📄license-compat] [![📄ilo-declaration-img]][📄ilo-declaration] [![Security Policy][🔐security-img]][🔐security] [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct] [![SemVer 2.0.0][📌semver-img]][📌semver] |
| Style                   | [![Enforced Code Style Linter][💎rlts-img]][💎rlts] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog] [![Gitmoji Commits][📌gitmoji-img]][📌gitmoji] [![Compatibility appraised by: appraisal2][💎appraisal2-img]][💎appraisal2]                                                                                                                  |
| Maintainer 🎖️          | [![Follow Me on LinkedIn][💖🖇linkedin-img]][💖🖇linkedin] [![Follow Me on Ruby.Social][💖🐘ruby-mast-img]][💖🐘ruby-mast] [![Follow Me on Bluesky][💖🦋bluesky-img]][💖🦋bluesky] [![Contact Maintainer][🚂maint-contact-img]][🚂maint-contact] [![My technical writing][💖💁🏼‍♂️devto-img]][💖💁🏼‍♂️devto]                                                      |
| `...` 💖                | [![Find Me on WellFound:][💖✌️wellfound-img]][💖✌️wellfound] [![Find Me on CrunchBase][💖💲crunchbase-img]][💖💲crunchbase] [![My LinkTree][💖🌳linktree-img]][💖🌳linktree] [![More About Me][💖💁🏼‍♂️aboutme-img]][💖💁🏼‍♂️aboutme] [🧊][💖🧊berg] [🐙][💖🐙hub]  [🛖][💖🛖hut] [🧪][💖🧪lab]                                                                   |

### Compatibility

Compatible with MRI Ruby 2.3.0+, and concordant releases of JRuby, and TruffleRuby.

| 🚚 _Amazing_ test matrix was brought to you by | 🔎 appraisal2 🔎 and the color 💚 green 💚             |
|------------------------------------------------|--------------------------------------------------------|
| 👟 Check it out!                               | ✨ [github.com/appraisal-rb/appraisal2][💎appraisal2] ✨ |

### Federated DVCS

<details markdown="1">
  <summary>Find this repo on federated forges (Coming soon!)</summary>

| Federated [DVCS][💎d-in-dvcs] Repository        | Status                                                                | Issues                    | PRs                      | Wiki                      | CI                       | Discussions                  |
|-------------------------------------------------|-----------------------------------------------------------------------|---------------------------|--------------------------|---------------------------|--------------------------|------------------------------|
| 🧪 [kettle-rb/kettle-dev on GitLab][📜src-gl]   | The Truth                                                             | [💚][🤝gl-issues]         | [💚][🤝gl-pulls]         | [💚][📜gl-wiki]           | 🐭 Tiny Matrix           | ➖                            |
| 🧊 [kettle-rb/kettle-dev on CodeBerg][📜src-cb] | An Ethical Mirror ([Donate][🤝cb-donate])                             | [💚][🤝cb-issues]         | [💚][🤝cb-pulls]         | ➖                         | ⭕️ No Matrix             | ➖                            |
| 🐙 [kettle-rb/kettle-dev on GitHub][📜src-gh]   | Another Mirror                                                        | [💚][🤝gh-issues]         | [💚][🤝gh-pulls]         | [💚][📜gh-wiki]           | 💯 Full Matrix           | [💚][gh-discussions]         |
| 🎮️ [Discord Server][✉️discord-invite]          | [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite] | [Let's][✉️discord-invite] | [talk][✉️discord-invite] | [about][✉️discord-invite] | [this][✉️discord-invite] | [library!][✉️discord-invite] |

</details>

[gh-discussions]: https://github.com/kettle-rb/kettle-dev/discussions

### Enterprise Support [![Tidelift](https://tidelift.com/badges/package/rubygems/kettle-dev)](https://tidelift.com/subscription/pkg/rubygems-kettle-dev?utm_source=rubygems-kettle-dev&utm_medium=referral&utm_campaign=readme)

Available as part of the Tidelift Subscription.

<details markdown="1">
  <summary>Need enterprise-level guarantees?</summary>

The maintainers of this and thousands of other packages are working with Tidelift to deliver commercial support and maintenance for the open source packages you use to build your applications. Save time, reduce risk, and improve code health, while paying the maintainers of the exact packages you use.

[![Get help from me on Tidelift][🏙️entsup-tidelift-img]][🏙️entsup-tidelift]

- 💡Subscribe for support guarantees covering _all_ your FLOSS dependencies
- 💡Tidelift is part of [Sonar][🏙️entsup-tidelift-sonar]
- 💡Tidelift pays maintainers to maintain the software you depend on!<br/>📊`@`Pointy Haired Boss: An [enterprise support][🏙️entsup-tidelift] subscription is "[never gonna let you down][🧮kloc]", and *supports* open source maintainers

Alternatively:

- [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite]
- [![Get help from me on Upwork][👨🏼‍🏫expsup-upwork-img]][👨🏼‍🏫expsup-upwork]
- [![Get help from me on Codementor][👨🏼‍🏫expsup-codementor-img]][👨🏼‍🏫expsup-codementor]

</details>

## ✨ Installation

Install the gem and add to the application's Gemfile by executing:

```console
bundle add kettle-dev
```

If bundler is not being used to manage dependencies, install the gem by executing:

```console
gem install kettle-dev
```

### 🔒 Secure Installation

<details markdown="1">
  <summary>For Medium or High Security Installations</summary>

This gem is cryptographically signed and has verifiable [SHA-256 and SHA-512][💎SHA_checksums] checksums by
[stone_checksums][💎stone_checksums]. Be sure the gem you install hasn’t been tampered with
by following the instructions below.

Add my public key (if you haven’t already; key expires 2045-04-29) as a trusted certificate:

```console
gem cert --add <(curl -Ls https://raw.github.com/galtzo-floss/certs/main/pboling.pem)
```

You only need to do that once.  Then proceed to install with:

```console
gem install kettle-dev -P HighSecurity
```

The `HighSecurity` trust profile will verify signed gems, and not allow the installation of unsigned dependencies.

If you want to up your security game full-time:

```console
bundle config set --global trust-policy MediumSecurity
```

`MediumSecurity` instead of `HighSecurity` is necessary if not all the gems you use are signed.

NOTE: Be prepared to track down certs for signed gems and add them the same way you added mine.

</details>

## ⚙️ Configuration

Note on executables vs Rake tasks

- Executable scripts provided by this gem (exe/\* and installed binstubs) work when the gem is installed as a system gem (gem install kettle-dev). They do not require the gem to be in your bundle to run.
- The Rake tasks provided by this gem require kettle-dev to be declared as a development dependency in your Gemfile and loaded in your project's Rakefile. Ensure your Gemfile includes:
  ```ruby
  group :development do
    gem "kettle-dev", require: false
  end
  ```
  And your Rakefile loads the gem's tasks, e.g.:
  ```ruby
  require "kettle/dev"
  ```

### RSpec

This gem integrates tightly with [kettle-test](https://github.com/kettle-rb/kettle-test).

```ruby
require "kettle/test/rspec"

# ... any other config you need to do.

# NOTE: Gemfiles for older rubies (< 2.7) won't have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => error
  # check the error message, and re-raise if not what is expected
  raise error unless error.message.include?("kettle")
end

# This gem (or app)
require "gem-under-test"
```

### Rakefile

Add to your `Rakefile`:

```ruby
require "kettle/dev"
```

Then run the one-time project bootstrapper:

```console
kettle-dev-setup
# Or to accept all defaults:
kettle-dev-setup --allowed=true --force
```

You'll be able to compare the changes with your diff tool, and certainly revert some of them.

For your protection:

- it won't run if git doesn't start out porcelain clean.
  After bootstrapping, to update the template to the latest version from a new release of this gem, run:

<!-- end list -->

```console
bundle exec rake kettle:dev:install
```

If git status is not clean it will abort.
It may have some prompts, which can mostly be avoided by running with options:

```console
# DANGER: options to reduce prompts will overwrite files without asking.
bundle exec rake kettle:dev:install allowed=true force=true
```

Hopefully, all the files that get overwritten are tracked in git\!
I wrote this for myself, and it fits my patterns of development.

The install task will write a report at the end with:

1.  A file list summary of the changes made.
2.  Next steps for using the tools.
3.  A warning about .env.local (DO NOT COMMIT IT, as it will likely have secrets added)
    That’s it. Once installed, kettle-dev:

<!-- end list -->

- Registers RuboCop-LTS tasks and wires your default Rake task to run the gradual linter.
    - Locally: default task prefers `rubocop_gradual:autocorrect`.
    - On CI (`CI=true`): default task prefers `rubocop_gradual:check`.
- Integrates optional coverage tasks via kettle-soup-cover (enabled locally when present).
- Adds gem-shipped Rake tasks from `lib/kettle/dev/rakelib`, including:
    - `ci:act` — interactive selector for running GitHub Actions workflows via `act`.
    - `kettle:dev:install` — copies this repo’s .github automation, offers to install .git-hooks templates, and overwrites many files in your project.
        - Grapheme syncing: detects the grapheme (e.g., emoji) immediately following the first `#` H1 in README.md and ensures the same grapheme, followed by a single space, prefixes both `spec.summary` and `spec.description` in your gemspec. If the H1 has none, you’ll be prompted to enter one; tests use an input adapter, so runs never hang in CI.
        - option: force: When truthy (1, true, y, yes), treat all y/N prompts as Yes. Useful for non-interactive runs or to accept defaults quickly. Example: `bundle exec rake kettle:dev:install force=true`
        - option: allowed: When truthy (1, true, y, yes), resume task after you have reviewed `.envrc`/`.env.local` and run `direnv allow`. If either file is created or updated, the task will abort with instructions unless `allowed=true` is present. Example: `bundle exec rake kettle:dev:install allowed=true`
        - option: only: A comma-separated list of glob patterns to include in templating. Any destination file whose path+filename does not match one of the patterns is excluded. Patterns are matched relative to your project root. Examples: `only="README.md,.github/**"`, `only="docs/**,lib/**/*.rb"`.
        - option: include: A comma-separated list of glob patterns that opt-in additional, non-default files. Currently, `.github/workflows/discord-notifier.yml` is not copied by default and will only be copied when `include` matches it (e.g., `include=".github/workflows/discord-notifier.yml"`).
    - `kettle:jem:template` (provided by [kettle-jem][kettle-jem]) — templates files from this gem into your project (e.g., .github workflows, .devcontainer, .qlty, modular Gemfiles, README/CONTRIBUTING stubs). You can run this independently to refresh templates without the extra install prompts.
        - option: force: When truthy (1, true, y, yes), treat all y/N prompts as Yes. Useful for non-interactive runs or to accept defaults quickly. Example: `bundle exec rake kettle:dev:install force=true`
        - option: allowed: When truthy (1, true, y, yes), resume task after you have reviewed `.envrc`/`.env.local` and run `direnv allow`. If either file is created or updated, the task will abort with instructions unless `allowed=true` is present. Example: `bundle exec rake kettle:jem:template allowed=true`
        - option: only: Same as for install; limits which destination files are written based on glob patterns relative to the project root.
        - option: include: Same as for install; opts into optional files (e.g., `.github/workflows/discord-notifier.yml`).
          Recommended one-time setup in your project:
- Install binstubs so kettle-dev executables are available under `./bin`:
    - `bundle binstubs kettle-dev --path bin`
- Use direnv (recommended) so `./bin` is on PATH automatically:
    - `brew install direnv`
    - In your project’s `.envrc` add:
        - `# Run any command in this library's bin/ without the bin/ prefix!`
        - `PATH_add bin`
- Configure shared git hooks path (optional, recommended):
    - `git config --global core.hooksPath .git-hooks`
- Install project automation and sample hooks/templates:
    - `bundle exec rake kettle:dev:install` and follow prompts (copies .github and installs .git-hooks templates locally or globally).
      See the next section for environment variables that tweak behavior.

### Environment Variables

Below are the primary environment variables recognized by kettle-dev (and its integrated tools). Unless otherwise noted, set boolean values to the string "true" to enable.

General/runtime

- `DEBUG`: Enable extra internal logging for this library (default: false)
- `REQUIRE_BENCH`: Enable `require_bench` to profile requires (default: false)
- `CI`: When set to true, adjusts default rake tasks toward CI behavior

Coverage (kettle-soup-cover / SimpleCov)

- `K_SOUP_COV_DO`: Enable coverage collection (default: true in .envrc)
- `K_SOUP_COV_FORMATTERS`: Comma-separated list of formatters (html, xml, rcov, lcov, json, tty)
- `K_SOUP_COV_MIN_LINE`: Minimum line coverage threshold (integer, e.g., 100)
- `K_SOUP_COV_MIN_BRANCH`: Minimum branch coverage threshold (integer, e.g., 100)
- `K_SOUP_COV_MIN_HARD`: Fail the run if thresholds are not met (true/false)
- `K_SOUP_COV_MULTI_FORMATTERS`: Enable multiple formatters at once (true/false)
- `K_SOUP_COV_OPEN_BIN`: Path to browser opener for HTML (empty disables auto-open)
- `MAX_ROWS`: Limit console output rows for simplecov-console (e.g., 1)

Tip: When running a single spec file locally, you may want `K_SOUP_COV_MIN_HARD=false` to avoid failing thresholds for a partial run.

GitHub API and CI helpers

- `GITHUB_TOKEN` or `GH_TOKEN`: Token used by `ci:act` and release workflow checks to query GitHub Actions status at higher rate limits
- `GITLAB_TOKEN` or `GL_TOKEN`: Token used by `ci:act` and CI monitor to query GitLab pipeline status

Releasing and signing

- `SKIP_GEM_SIGNING`: If set, skip gem signing during build/release
- `GEM_CERT_USER`: Username for selecting your public cert in `certs/<USER>.pem` (defaults to $USER)
- `SOURCE_DATE_EPOCH`: Reproducible build timestamp. `kettle-release` will set this automatically for the session.

Git hooks and commit message helpers (exe/kettle-commit-msg)

- `GIT_HOOK_BRANCH_VALIDATE`: Branch name validation mode (e.g., `jira`) or `false` to disable
- `GIT_HOOK_FOOTER_APPEND`: Append a footer to commit messages when goalie allows (true/false)
- `GIT_HOOK_FOOTER_SENTINEL`: Required when footer append is enabled — a unique first-line sentinel to prevent duplicates
- `GIT_HOOK_FOOTER_APPEND_DEBUG`: Extra debug output in the footer template (true/false)

For a quick starting point, this repository’s `.envrc` shows sane defaults, and `.env.local` can override them locally.

## 🔧 Basic Usage

Common flows

- Default quality workflow (locally):
    - `bundle exec rake` — runs the curated default task set (gradual RuboCop autocorrect, coverage if available, and other local tasks). On CI `CI=true`, the default task is adjusted to be CI-friendly.
- Run specs:
    - `bin/rspec` or `bundle exec rspec`
    - To run a subset without failing coverage thresholds: `K_SOUP_COV_MIN_HARD=false bin/rspec spec/path/to/file_spec.rb`
    - To produce multiple coverage reports: `K_SOUP_COV_FORMATTERS="html,xml,rcov,lcov,json,tty" bin/rspec`
- Linting (Gradual):
    - `bundle exec rake rubocop_gradual:autocorrect`
    - `bundle exec rake rubocop_gradual:check` (CI-friendly)
- Reek and docs:
    - `bundle exec rake reek` or `bundle exec rake reek:update`
    - `bundle exec rake yard`
      [Appraisals][💎appraisal2] helpers
- `bundle exec rake appraisal:isntall` — First time Appraisal setup.
- `bundle exec rake appraisal:update` — Update Appraisal gemfiles and run RuboCop Gradual autocorrect.
- `bundle exec rake appraisal:reset` — Delete all Appraisal lockfiles in gemfiles/ (\*.gemfile.lock). Useful before regenerating appraisals or when switching Ruby versions.
  GitHub Actions local runner helper
- `bundle exec rake ci:act` — interactive menu shows workflows from `.github/workflows` with live status and short codes (first 3 letters of file name). Type a number or short code.
- Non-interactive: `bundle exec rake ci:act[loc]` (short code), or `bundle exec rake ci:act[locked_deps.yml]` (filename).
  Setup tokens for API status (GitHub and GitLab)
- Purpose: ci:act displays the latest status for GitHub Actions runs and (when applicable) the latest GitLab pipeline for the current branch. Unauthenticated requests are rate-limited; private repositories require tokens. Provide tokens to get reliable status.
- GitHub token (recommended: fine-grained):
    - Where to create: https://github.com/settings/personal-access-tokens
        - Fine-grained: “Tokens (fine-grained)” → Generate new token
        - Classic (fallback): “Tokens (classic)” → Generate new token
    - Minimum permissions:
        - Fine-grained: Repository access: Read-only for the target repository (or your org); Permissions → Actions: Read
        - Classic: For public repos, no scopes are strictly required, but rate limits are very low; for private repos, include the repo scope
    - Add to environment (`.env.local` via `direnv`):
        - `GITHUB_TOKEN=your_token_here`  (or `GH_TOKEN=…`)
- GitLab token:
    - Where to create: [gitlab.com](https://gitlab.com/-/user_settings/personal_access_tokens)
    - Minimum scope: `read_api` (sufficient to read pipelines)
    - Add to environment (.env.local via direnv):
        - `GITLAB_TOKEN=your_token_here`  (or `GL_TOKEN=…`)
- Load environment:
    - Save tokens in `.env.local` (never commit this file), then run: `direnv allow`
- Verify:
    - Run: bundle exec rake ci:act
    - The header will include Repo/Upstream/HEAD; entries will show “Latest GHA …” and “Latest GL … pipeline” with emoji status. On failure to authenticate or rate-limit, you’ll see a brief error/result code.
      Project automation bootstrap
- `bundle exec rake kettle:dev:install` — copies the library’s `.github` folder into your project and offers to install `.git-hooks` templates locally or globally.
- `bundle exec rake kettle:jem:template` — runs only the templating step used by install; useful to re-apply updates to templates (.github workflows, .devcontainer, .qlty, modular Gemfiles, README, and friends) without the `install` task’s extra prompts.
    - Also copies maintainer certificate `certs/pboling.pem` into your project when present (used for signed gem builds).
    - README carry-over during templating: when your project’s README.md is replaced by the template, selected sections from your existing README are preserved and merged into the new one. Specifically, the task carries over the following sections (matched case-insensitively):
        - "Synopsis"
        - "Configuration"
        - "Basic Usage"
        - Any section whose heading starts with "Note:" at any heading level (for example: "\# NOTE: …", "\#\# Note: …", or "\#\#\# note: …").
        - Headings are recognized at any level using Markdown hashes (\#, \#\#, \#\#\#, …).
- Notes about task options:
    - Non-interactive confirmations: append `force=true` to accept all y/N prompts as Yes, e.g., `bundle exec rake kettle:jem:template force=true`.
    - direnv review flow: if `.envrc` or `.env.local` is created or updated, the task stops and asks you to run `direnv allow`. After you review and allow, resume with `allowed=true`:
        - `bundle exec rake kettle:jem:template allowed=true`
        - `bundle exec rake kettle:dev:install allowed=true`
- After that, set up binstubs and direnv for convenience:
    - `bundle binstubs kettle-dev --path bin`
    - Add to `.envrc`: `PATH_add bin` (so `bin/` tools run without the prefix)

### kettle-dvcs (normalize multi-forge remotes)

- Script: `exe/kettle-dvcs` (install binstubs for convenience: `bundle binstubs kettle-dev --path bin`)
- Purpose: Normalize git remotes across GitHub, GitLab, and Codeberg, and create an `all` remote that pushes to all and fetches only from your chosen origin.
- Assumptions: org and repo names are identical across forges.
  Usage:

<!-- end list -->

```console
kettle-dvcs [options] [ORG] [REPO]
```

Options:

- `--origin [github|gitlab|codeberg]` Which forge to use as `origin` (default: github)
- `--protocol [ssh|https]` URL style (default: ssh)
- `--github-name NAME` Remote name for GitHub when not origin (default: gh)
- `--gitlab-name NAME` Remote name for GitLab (default: gl)
- `--codeberg-name NAME` Remote name for Codeberg (default: cb)
- `--force` Non-interactive; accept defaults, and do not prompt for ORG/REPO
  Examples:
- Default, interactive (infers ORG/REPO from an existing remote when possible):
  ```console
  kettle-dvcs
  ```
- Non-interactive with explicit org/repo:
  ```console
  kettle-dvcs --force my-org my-repo
  ```
- Use GitLab as origin and HTTPS URLs:
  ```console
  kettle-dvcs --origin gitlab --protocol https my-org my-repo
  ```

What it does:

- Ensures remotes exist and have consistent URLs for each forge.
- Renames existing remotes when their URL already matches the desired target but their name does not (e.g., `gitlab` -\> `gl`).
- Creates/refreshes an `all` remote that:
    - fetches only from your chosen `origin` forge.
    - has pushurls configured for all three forges so `git push all <branch>` updates all mirrors.
- Prints `git remote -v` at the end.
- Attempts to `git fetch` each forge remote to check availability:
    - If all succeed, the README’s federated DVCS summary line has “(Coming soon\!)” removed.
    - If any fail, the script prints import links to help you create a mirror on that forge.

### Releasing (maintainers)

- Script: `exe/kettle-release` (run as `kettle-release`)
- Purpose: guided release helper that:
    - Runs sanity checks (`bin/setup`, `bin/rake`), confirms version/changelog, optionally updates Appraisals, regenerates docs via `bin/rake yard`, commits “🔖 Prepare release vX.Y.Z”.
    - Optionally runs your CI locally with `act` before any push:
        - Enable with env: `K_RELEASE_LOCAL_CI="true"` (run automatically) or `K_RELEASE_LOCAL_CI="ask"` (prompt \[Y/n\]).
        - Select workflow with `K_RELEASE_LOCAL_CI_WORKFLOW` (with or without .yml/.yaml). Defaults to `locked_deps.yml` if present; otherwise the first workflow discovered.
        - On failure, the release prep commit is soft-rolled-back (`git reset --soft HEAD^`) and the process aborts.
    - Ensures trunk sync and rebases feature as needed, pushes, monitors GitHub Actions with a progress bar, and merges feature to trunk on success.
    - Exports `SOURCE_DATE_EPOCH`, builds (optionally signed), creates gem checksums, and runs `bundle exec rake release` (prompts for signing key + RubyGems MFA OTP as needed).
- Options:
    - `start_step` map (skip directly to a phase):
        1.  Verify Bundler \>= 2.7 (always runs; start at 1 to do everything)
        2.  Detect version; RubyGems sanity check; confirm CHANGELOG/version; sync copyright years; update badges/headers
        3.  Run bin/setup
        4.  Run bin/rake (default task)
        5.  Run bin/rake appraisal:update if Appraisals present, then bin/rake yard
        6.  Ensure git user configured; commit release prep
        7.  Optional local CI with `act` (controlled by `K_RELEASE_LOCAL_CI`)
        8.  Ensure trunk in sync across remotes; rebase feature as needed
        9.  Push current branch to remotes (or 'all' remote)
        10. Monitor CI after push; abort on failures
        11. Merge feature into trunk and push
        12. Checkout trunk and pull latest
        13. Gem signing checks/guidance (skip with `SKIP_GEM_SIGNING=true`)
        14. Build gem (bundle exec rake build)
        15. Release gem (bundle exec rake release)
        16. Generate and validate checksums (`bin/gem_checksums`)
        17. Push checksum commit
        18. Create GitHub Release (requires `GITHUB_TOKEN`)
        19. Push tags to remotes (final)
- Examples:
    - After intermittent CI failure, restart from monitoring: `bundle exec kettle-release start_step=10`
- Tips:
    - The commit message helper `exe/kettle-commit-msg` prefers project-local `.git-hooks` (then falls back to `~/.git-hooks`).
    - The goalie file `commit-subjects-goalie.txt` controls when a footer is appended; customize `footer-template.erb.txt` as you like.

### Changelog generator

- Script: `exe/kettle-changelog` (run as `kettle-changelog`)
- Purpose: Generates a new CHANGELOG.md section for the current version read from `lib/**/version.rb`, moves notes from the Unreleased section, and updates comparison links.
- Prerequisites:
    - `coverage/coverage.json` present (generate with: `K_SOUP_COV_FORMATTERS="json" bin/rspec`).
    - `bin/rake yard` available, to compute documentation coverage.
- Usage:
    - `kettle-changelog`
- Behavior:
    - Reads version from the unique `lib/**/version.rb` in the project.
    - Moves entries from the `[Unreleased]` section into a new `[#.#.#] - YYYY-MM-DD` section.
    - Prepends 4 lines with TAG, line coverage, branch coverage, and percent documented.
    - Converts any GitLab-style compare links at the bottom to GitHub style, adds new tag/compare links for the new release and a temporary tag reference `[X.Y.Zt]`.

### Pre-release checks

- Script: `exe/kettle-pre-release` (run as `kettle-pre-release`)
- Purpose: Run a suite of pre-release validations to catch avoidable mistakes (resumable by check number).
- Usage:
    - `kettle-pre-release [--check-num N]`
    - Short option: `kettle-pre-release -cN`
- Options:
    - `--check-num N` Start from check number N (default: 1)
- Checks:
    - 1)  Validate that all image URLs referenced by Markdown files resolve (HTTP HEAD)

### Commit message helper (git hook)

- Script: `exe/kettle-commit-msg` (run by git as `.git/hooks/commit-msg`)
- Purpose: Append a standardized footer and optionally enforce branch naming rules when configured.
- Usage:
    - Git invokes this with the path to the commit message file: `kettle-commit-msg .git/COMMIT_EDITMSG`
    - Install via `bundle exec rake kettle:dev:install` to copy hook templates into `.git-hooks` and wire them up.
- Behavior:
    - When `GIT_HOOK_BRANCH_VALIDATE=jira`, validates the current branch matches the pattern: `^(hotfix|bug|feature|candy)/[0-9]{8,}-…`.
        - If it matches and the commit message lacks the numeric ID, appends `[<type>][<id>]`.
    - Always invokes `Kettle::Dev::GitCommitFooter.render` to potentially append a footer if allowed by the goalie.
    - Prefers project-local `.git-hooks` templates; falls back to `~/.git-hooks`.
- Environment:
    - `GIT_HOOK_BRANCH_VALIDATE` Branch rule (e.g., `jira`) or `false` to disable.
    - `GIT_HOOK_FOOTER_APPEND` Enable footer auto-append when goalie allows (true/false).
    - `GIT_HOOK_FOOTER_SENTINEL` Required marker to avoid duplicate appends when enabled.
    - `GIT_HOOK_FOOTER_APPEND_DEBUG` Extra debug output in the footer template (true/false).

### Project bootstrap installer

- Script: `exe/kettle-dev-setup` (run as `kettle-dev-setup`)
- Purpose: Bootstrap a host gem repository to use kettle-dev’s tooling without manual steps.
- Usage:
    - `kettle-dev-setup [options] [passthrough args]`
- Options (mapped through to `rake kettle:dev:install`):
    - `--allowed=VAL` Pass `allowed=VAL` to acknowledge prior direnv allow, etc.
    - `--force` Pass `force=true` to accept prompts non-interactively.
    - `--hook_templates=VAL` Pass `hook_templates=VAL` to control git hook templating.
    - `--only=VAL` Pass `only=VAL` to restrict install scope.
    - `--include=VAL` Pass `include=VAL` to include optional files by glob (see notes below).
    - `-h`, `--help` Show help.
- Behavior:
    - Verifies a clean git working tree, presence of a Gemfile and a gemspec.
    - Syncs development dependencies from this gem’s example gemspec into the target gemspec (replacing or inserting `add_development_dependency` lines as needed).
    - Ensures `bin/setup` exists (copies from gem if missing) and replaces/creates the project’s `Rakefile` from `Rakefile.example`.
    - Runs `bin/setup`, then `bundle exec bundle binstubs --all`.
    - Stages and commits any bootstrap changes with message: `🎨 Template bootstrap by kettle-dev-setup v<version>`.
    - Executes `bin/rake kettle:dev:install` with the parsed passthrough args.

### Open Collective README updater

- Script: `exe/kettle-readme-backers` (run as `kettle-readme-backers`)
- Purpose: Updates README sections for Open Collective backers (individuals) and sponsors (organizations) by fetching live data from your collective.
- Tags updated in README.md (first match wins for backers):
    - The default tag prefix is `OPENCOLLECTIVE`, and it is configurable:
        - ENV: `KETTLE_DEV_BACKER_README_OSC_TAG="OPENCOLLECTIVE"`
        - YAML (.opencollective.yml): `readme-osc-tag: "OPENCOLLECTIVE"`
        - The resulting markers become: `<!-- <TAG>:START --> … <!-- <TAG>:END -->`, `<!-- <TAG>-INDIVIDUALS:START --> … <!-- <TAG>-INDIVIDUALS:END -->`, and `<!-- <TAG>-ORGANIZATIONS:START --> … <!-- <TAG>-ORGANIZATIONS:END -->`.
        - ENV overrides YAML.
    - Backers (Individuals): `<!-- <TAG>:START --> … <!-- <TAG>:END -->` or `<!-- <TAG>-INDIVIDUALS:START --> … <!-- <TAG>-INDIVIDUALS:END -->`
    - Sponsors (Organizations): `<!-- <TAG>-ORGANIZATIONS:START --> … <!-- <TAG>-ORGANIZATIONS:END -->`
- Handle resolution:
    1.  `OPENCOLLECTIVE_HANDLE` environment variable, if set
    2.  `opencollective.yml` in the project root (e.g., `collective: "kettle-rb"` in this repo)
- Usage:
    - `exe/kettle-readme-backers`
    - `OPENCOLLECTIVE_HANDLE=my-collective exe/kettle-readme-backers`
- Behavior:
    - Writes to README.md only if content between the tags would change.
    - If neither the backers nor sponsors tags are present, prints a helpful warning and exits with status 2.
    - When there are no entries, inserts a friendly placeholder: "No backers yet. Be the first\!" or "No sponsors yet. Be the first\!".
    - When updates are written and the repository is a git work tree, the script stages README.md and commits with a message thanking new backers and subscribers, including mentions for any newly added backers and subscribers (GitHub @handles when their website/profile is a github.com URL; otherwise their name).
    - Customize the commit subject via env var: `KETTLE_README_BACKERS_COMMIT_SUBJECT="💸 Thanks 🙏 to our new backers 🎒 and subscribers 📜"`.
        - Or via .opencollective.yml: set `readme-backers-commit-subject: "💸 Thanks 🙏 to our new backers 🎒 and subscribers 📜"`.
        - Precedence: ENV overrides .opencollective.yml; if neither is set, a sensible default is used.
        - Note: When used with the provided `.git-hooks`, the subject should start with a gitmoji character (see [gitmoji][📌gitmoji]).
- Tip:
    - Run this locally before committing to keep your README current, or schedule it in CI to refresh periodically.
    - It runs automatically on a once-a-week schedule by the .github/workflows/opencollective.yml workflow that is part of the kettle-jem template.
- Authentication requirement:
    - When running in CI with the provided workflow, you must provide an organization-level Actions secret named `README_UPDATER_TOKEN`.
        - Create it under your GitHub organization settings: `https://github.com/organizations/<YOUR_ORG>/settings/secrets/actions`.
        - The updater will look for `REPO` or `GITHUB_REPOSITORY` (both usually set by GitHub Actions) to infer `<YOUR_ORG>` for guidance.
        - If `README_UPDATER_TOKEN` is missing, the tool prints a helpful error to STDERR and aborts, including a direct link to the expected org settings page.

## 🦷 FLOSS Funding

While kettle-rb tools are free software and will always be, the project would benefit immensely from some funding.
Raising a monthly budget of... "dollars" would make the project more sustainable.

We welcome both individual and corporate sponsors! We also offer a
wide array of funding channels to account for your preferences
(although currently [Open Collective][🖇osc] is our preferred funding platform).

**If you're working in a company that's making significant use of kettle-rb tools we'd
appreciate it if you suggest to your company to become a kettle-rb sponsor.**

You can support the development of kettle-rb tools via
[GitHub Sponsors][🖇sponsor],
[Liberapay][⛳liberapay],
[PayPal][🖇paypal],
[Open Collective][🖇osc]
and [Tidelift][🏙️entsup-tidelift].

| 📍 NOTE                                                                                                                                                                                                              |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| If doing a sponsorship in the form of donation is problematic for your company <br/> from an accounting standpoint, we'd recommend the use of Tidelift, <br/> where you can get a support-like subscription instead. |

### Open Collective for Individuals

Support us with a monthly donation and help us continue our activities. [[Become a backer](https://opencollective.com/kettle-rb#backer)]

NOTE: [kettle-readme-backers][kettle-readme-backers] updates this list every day, automatically.

<!-- OPENCOLLECTIVE-INDIVIDUALS:START -->
No backers yet. Be the first!
<!-- OPENCOLLECTIVE-INDIVIDUALS:END -->

### Open Collective for Organizations

Become a sponsor and get your logo on our README on GitHub with a link to your site. [[Become a sponsor](https://opencollective.com/kettle-rb#sponsor)]

NOTE: [kettle-readme-backers][kettle-readme-backers] updates this list every day, automatically.

<!-- OPENCOLLECTIVE-ORGANIZATIONS:START -->
No sponsors yet. Be the first!
<!-- OPENCOLLECTIVE-ORGANIZATIONS:END -->

[kettle-readme-backers]: https://github.com/kettle-rb/kettle-dev/blob/main/exe/kettle-readme-backers

### Another way to support open-source

I’m driven by a passion to foster a thriving open-source community – a space where people can tackle complex problems, no matter how small.  Revitalizing libraries that have fallen into disrepair, and building new libraries focused on solving real-world challenges, are my passions.  I was recently affected by layoffs, and the tech jobs market is unwelcoming. I’m reaching out here because your support would significantly aid my efforts to provide for my family, and my farm (11 🐔 chickens, 2 🐶 dogs, 3 🐰 rabbits, 8 🐈‍ cats).

If you work at a company that uses my work, please encourage them to support me as a corporate sponsor. My work on gems you use might show up in `bundle fund`.

I’m developing a new library, [floss_funding][🖇floss-funding-gem], designed to empower open-source developers like myself to get paid for the work we do, in a sustainable way. Please give it a look.

**[Floss-Funding.dev][🖇floss-funding.dev]: 👉️ No network calls. 👉️ No tracking. 👉️ No oversight. 👉️ Minimal crypto hashing. 💡 Easily disabled nags**

[![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] [![Donate on PayPal][🖇paypal-img]][🖇paypal] [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate on Polar][🖇polar-img]][🖇polar] [![Donate to my FLOSS efforts at ko-fi.com][🖇kofi-img]][🖇kofi] [![Donate to my FLOSS efforts using Patreon][🖇patreon-img]][🖇patreon]

## 🔐 Security

See [SECURITY.md][🔐security].

## 🤝 Contributing

If you need some ideas of where to help, you could work on adding more code coverage,
or if it is already 💯 (see [below](#code-coverage)) check [issues][🤝gh-issues] or [PRs][🤝gh-pulls],
or use the gem and think about how it could be better.

We [![Keep A Changelog][📗keep-changelog-img]][📗keep-changelog] so if you make changes, remember to update it.

See [CONTRIBUTING.md][🤝contributing] for more detailed instructions.

### 🚀 Release Instructions

See [CONTRIBUTING.md][🤝contributing].

### Code Coverage

[![Coverage Graph][🏀codecov-g]][🏀codecov]

[![Coveralls Test Coverage][🏀coveralls-img]][🏀coveralls]

[![QLTY Test Coverage][🏀qlty-covi]][🏀qlty-cov]

### 🪇 Code of Conduct

Everyone interacting with this project's codebases, issue trackers,
chat rooms and mailing lists agrees to follow the [![Contributor Covenant 2.1][🪇conduct-img]][🪇conduct].

## 🌈 Contributors

[![Contributors][🖐contributors-img]][🖐contributors]

Made with [contributors-img][🖐contrib-rocks].

Also see GitLab Contributors: [https://gitlab.com/kettle-rb/kettle-dev/-/graphs/main][🚎contributors-gl]

<details>
    <summary>⭐️ Star History</summary>

<a href="https://star-history.com/#kettle-rb/kettle-dev&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=kettle-rb/kettle-dev&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=kettle-rb/kettle-dev&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=kettle-rb/kettle-dev&type=Date" />
 </picture>
</a>

</details>

## 📌 Versioning

This Library adheres to [![Semantic Versioning 2.0.0][📌semver-img]][📌semver].
Violations of this scheme should be reported as bugs.
Specifically, if a minor or patch version is released that breaks backward compatibility,
a new version should be immediately released that restores compatibility.
Breaking changes to the public API will only be introduced with new major versions.

> dropping support for a platform is both obviously and objectively a breaking change <br/>
>—Jordan Harband ([@ljharb](https://github.com/ljharb), maintainer of SemVer) [in SemVer issue 716][📌semver-breaking]

I understand that policy doesn't work universally ("exceptions to every rule!"),
but it is the policy here.
As such, in many cases it is good to specify a dependency on this library using
the [Pessimistic Version Constraint][📌pvc] with two digits of precision.

For example:

```ruby
spec.add_dependency("kettle-dev", "~> 2.0")
```

<details markdown="1">
<summary>📌 Is "Platform Support" part of the public API? More details inside.</summary>

SemVer should, IMO, but doesn't explicitly, say that dropping support for specific Platforms
is a *breaking change* to an API, and for that reason the bike shedding is endless.

To get a better understanding of how SemVer is intended to work over a project's lifetime,
read this article from the creator of SemVer:

- ["Major Version Numbers are Not Sacred"][📌major-versions-not-sacred]

</details>

See [CHANGELOG.md][📌changelog] for a list of releases.

## 📄 License

The gem is available under the following license: [AGPL-3.0-only](AGPL-3.0-only.md).
See [LICENSE.md][📄license] for details.

If none of the available licenses suit your use case, please [contact us](mailto:floss@galtzo.com) to discuss a custom commercial license.

### © Copyright

See [LICENSE.md][📄license] for the official copyright notice.

## 🤑 A request for help

Maintainers have teeth and need to pay their dentists.
After getting laid off in an RIF in March, and encountering difficulty finding a new one,
I began spending most of my time building open source tools.
I'm hoping to be able to pay for my kids' health insurance this month,
so if you value the work I am doing, I need your support.
Please consider sponsoring me or the project.

To join the community or get help 👇️ Join the Discord.

[![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite]

To say "thanks!" ☝️ Join the Discord or 👇️ send money.

[![Sponsor kettle-rb/kettle-dev on Open Source Collective][🖇osc-all-bottom-img]][🖇osc] 💌 [![Sponsor me on GitHub Sponsors][🖇sponsor-bottom-img]][🖇sponsor] 💌 [![Sponsor me on Liberapay][⛳liberapay-bottom-img]][⛳liberapay] 💌 [![Donate on PayPal][🖇paypal-bottom-img]][🖇paypal]

### Please give the project a star ⭐ ♥.

Thanks for RTFM. ☺️

[⛳liberapay-img]: https://img.shields.io/liberapay/goal/pboling.svg?logo=liberapay&color=a51611&style=flat
[⛳liberapay-bottom-img]: https://img.shields.io/liberapay/goal/pboling.svg?style=for-the-badge&logo=liberapay&color=a51611
[⛳liberapay]: https://liberapay.com/pboling/donate
[🖇osc-all-img]: https://img.shields.io/opencollective/all/kettle-rb
[🖇osc-sponsors-img]: https://img.shields.io/opencollective/sponsors/kettle-rb
[🖇osc-backers-img]: https://img.shields.io/opencollective/backers/kettle-rb
[🖇osc-backers]: https://opencollective.com/kettle-rb#backer
[🖇osc-backers-i]: https://opencollective.com/kettle-rb/backers/badge.svg?style=flat
[🖇osc-sponsors]: https://opencollective.com/kettle-rb#sponsor
[🖇osc-sponsors-i]: https://opencollective.com/kettle-rb/sponsors/badge.svg?style=flat
[🖇osc-all-bottom-img]: https://img.shields.io/opencollective/all/kettle-rb?style=for-the-badge
[🖇osc-sponsors-bottom-img]: https://img.shields.io/opencollective/sponsors/kettle-rb?style=for-the-badge
[🖇osc-backers-bottom-img]: https://img.shields.io/opencollective/backers/kettle-rb?style=for-the-badge
[🖇osc]: https://opencollective.com/kettle-rb
[🖇sponsor-img]: https://img.shields.io/badge/Sponsor_Me!-pboling.svg?style=social&logo=github
[🖇sponsor-bottom-img]: https://img.shields.io/badge/Sponsor_Me!-pboling-blue?style=for-the-badge&logo=github
[🖇sponsor]: https://github.com/sponsors/pboling
[🖇polar-img]: https://img.shields.io/badge/polar-donate-a51611.svg?style=flat
[🖇polar]: https://polar.sh/pboling
[🖇kofi-img]: https://img.shields.io/badge/ko--fi-%E2%9C%93-a51611.svg?style=flat
[🖇kofi]: https://ko-fi.com/pboling
[🖇patreon-img]: https://img.shields.io/badge/patreon-donate-a51611.svg?style=flat
[🖇patreon]: https://patreon.com/galtzo
[🖇buyme-small-img]: https://img.shields.io/badge/buy_me_a_coffee-%E2%9C%93-a51611.svg?style=flat
[🖇buyme-img]: https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20latte&emoji=&slug=pboling&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff
[🖇buyme]: https://www.buymeacoffee.com/pboling
[🖇paypal-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=flat&logo=paypal
[🖇paypal-bottom-img]: https://img.shields.io/badge/donate-paypal-a51611.svg?style=for-the-badge&logo=paypal&color=0A0A0A
[🖇paypal]: https://www.paypal.com/paypalme/peterboling
[🖇floss-funding.dev]: https://floss-funding.dev
[🖇floss-funding-gem]: https://github.com/galtzo-floss/floss_funding
[✉️discord-invite]: https://discord.gg/3qme4XHNKN
[✉️discord-invite-img-ftb]: https://img.shields.io/discord/1373797679469170758?style=for-the-badge&logo=discord
[✉️ruby-friends-img]: https://img.shields.io/badge/daily.dev-%F0%9F%92%8E_Ruby_Friends-0A0A0A?style=for-the-badge&logo=dailydotdev&logoColor=white
[✉️ruby-friends]: https://app.daily.dev/squads/rubyfriends

[✇bundle-group-pattern]: https://gist.github.com/pboling/4564780
[⛳️gem-namespace]: https://github.com/kettle-rb/kettle-dev
[⛳️namespace-img]: https://img.shields.io/badge/namespace-Kettle::Dev-3C2D2D.svg?style=square&logo=ruby&logoColor=white
[⛳️gem-name]: https://bestgems.org/gems/kettle-dev
[⛳️name-img]: https://img.shields.io/badge/name-kettle--dev-3C2D2D.svg?style=square&logo=rubygems&logoColor=red
[⛳️tag-img]: https://img.shields.io/github/tag/kettle-rb/kettle-dev.svg
[⛳️tag]: http://github.com/kettle-rb/kettle-dev/releases
[🚂maint-blog]: http://www.railsbling.com/tags/kettle-dev
[🚂maint-blog-img]: https://img.shields.io/badge/blog-railsbling-0093D0.svg?style=for-the-badge&logo=rubyonrails&logoColor=orange
[🚂maint-contact]: http://www.railsbling.com/contact
[🚂maint-contact-img]: https://img.shields.io/badge/Contact-Maintainer-0093D0.svg?style=flat&logo=rubyonrails&logoColor=red
[💖🖇linkedin]: http://www.linkedin.com/in/peterboling
[💖🖇linkedin-img]: https://img.shields.io/badge/LinkedIn-Profile-0B66C2?style=flat&logo=newjapanprowrestling
[💖✌️wellfound]: https://wellfound.com/u/peter-boling
[💖✌️wellfound-img]: https://img.shields.io/badge/peter--boling-orange?style=flat&logo=wellfound
[💖💲crunchbase]: https://www.crunchbase.com/person/peter-boling
[💖💲crunchbase-img]: https://img.shields.io/badge/peter--boling-purple?style=flat&logo=crunchbase
[💖🐘ruby-mast]: https://ruby.social/@galtzo
[💖🐘ruby-mast-img]: https://img.shields.io/mastodon/follow/109447111526622197?domain=https://ruby.social&style=flat&logo=mastodon&label=Ruby%20@galtzo
[💖🦋bluesky]: https://bsky.app/profile/galtzo.com
[💖🦋bluesky-img]: https://img.shields.io/badge/@galtzo.com-0285FF?style=flat&logo=bluesky&logoColor=white
[💖🌳linktree]: https://linktr.ee/galtzo
[💖🌳linktree-img]: https://img.shields.io/badge/galtzo-purple?style=flat&logo=linktree
[💖💁🏼‍♂️devto]: https://dev.to/galtzo
[💖💁🏼‍♂️devto-img]: https://img.shields.io/badge/dev.to-0A0A0A?style=flat&logo=devdotto&logoColor=white
[💖💁🏼‍♂️aboutme]: https://about.me/peter.boling
[💖💁🏼‍♂️aboutme-img]: https://img.shields.io/badge/about.me-0A0A0A?style=flat&logo=aboutme&logoColor=white
[💖🧊berg]: https://codeberg.org/pboling
[💖🐙hub]: https://github.org/pboling
[💖🛖hut]: https://sr.ht/~galtzo/
[💖🧪lab]: https://gitlab.com/pboling
[👨🏼‍🏫expsup-upwork]: https://www.upwork.com/freelancers/~014942e9b056abdf86?mp_source=share
[👨🏼‍🏫expsup-upwork-img]: https://img.shields.io/badge/UpWork-13544E?style=for-the-badge&logo=Upwork&logoColor=white
[👨🏼‍🏫expsup-codementor]: https://www.codementor.io/peterboling?utm_source=github&utm_medium=button&utm_term=peterboling&utm_campaign=github
[👨🏼‍🏫expsup-codementor-img]: https://img.shields.io/badge/CodeMentor-Get_Help-1abc9c?style=for-the-badge&logo=CodeMentor&logoColor=white
[🏙️entsup-tidelift]: https://tidelift.com/subscription/pkg/rubygems-kettle-dev?utm_source=rubygems-kettle-dev&utm_medium=referral&utm_campaign=readme
[🏙️entsup-tidelift-img]: https://img.shields.io/badge/Tidelift_and_Sonar-Enterprise_Support-FD3456?style=for-the-badge&logo=sonar&logoColor=white
[🏙️entsup-tidelift-sonar]: https://blog.tidelift.com/tidelift-joins-sonar
[💁🏼‍♂️peterboling]: http://www.peterboling.com
[🚂railsbling]: http://www.railsbling.com
[📜src-gl-img]: https://img.shields.io/badge/GitLab-FBA326?style=for-the-badge&logo=Gitlab&logoColor=orange
[📜src-gl]: https://gitlab.com/kettle-rb/kettle-dev/
[📜src-cb-img]: https://img.shields.io/badge/CodeBerg-4893CC?style=for-the-badge&logo=CodeBerg&logoColor=blue
[📜src-cb]: https://codeberg.org/kettle-rb/kettle-dev
[📜src-gh-img]: https://img.shields.io/badge/GitHub-238636?style=for-the-badge&logo=Github&logoColor=green
[📜src-gh]: https://github.com/kettle-rb/kettle-dev
[📜docs-cr-rd-img]: https://img.shields.io/badge/RubyDoc-Current_Release-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜docs-head-rd-img]: https://img.shields.io/badge/YARD_on_Galtzo.com-HEAD-943CD2?style=for-the-badge&logo=readthedocs&logoColor=white
[📜gl-wiki]: https://gitlab.com/kettle-rb/kettle-dev/-/wikis/home
[📜gh-wiki]: https://github.com/kettle-rb/kettle-dev/wiki
[📜gl-wiki-img]: https://img.shields.io/badge/wiki-examples-943CD2.svg?style=for-the-badge&logo=gitlab&logoColor=white
[📜gh-wiki-img]: https://img.shields.io/badge/wiki-examples-943CD2.svg?style=for-the-badge&logo=github&logoColor=white
[👽dl-rank]: https://bestgems.org/gems/kettle-dev
[👽dl-ranki]: https://img.shields.io/gem/rd/kettle-dev.svg
[👽oss-help]: https://www.codetriage.com/kettle-rb/kettle-dev
[👽oss-helpi]: https://www.codetriage.com/kettle-rb/kettle-dev/badges/users.svg
[👽version]: https://bestgems.org/gems/kettle-dev
[👽versioni]: https://img.shields.io/gem/v/kettle-dev.svg
[🏀qlty-mnt]: https://qlty.sh/gh/kettle-rb/projects/kettle-dev
[🏀qlty-mnti]: https://qlty.sh/gh/kettle-rb/projects/kettle-dev/maintainability.svg
[🏀qlty-cov]: https://qlty.sh/gh/kettle-rb/projects/kettle-dev/metrics/code?sort=coverageRating
[🏀qlty-covi]: https://qlty.sh/gh/kettle-rb/projects/kettle-dev/coverage.svg
[🏀codecov]: https://codecov.io/gh/kettle-rb/kettle-dev
[🏀codecovi]: https://codecov.io/gh/kettle-rb/kettle-dev/graph/badge.svg
[🏀coveralls]: https://coveralls.io/github/kettle-rb/kettle-dev?branch=main
[🏀coveralls-img]: https://coveralls.io/repos/github/kettle-rb/kettle-dev/badge.svg?branch=main
[🖐codeQL]: https://github.com/kettle-rb/kettle-dev/security/code-scanning
[🖐codeQL-img]: https://github.com/kettle-rb/kettle-dev/actions/workflows/codeql-analysis.yml/badge.svg
[🚎ruby-2.3-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-2.3.yml
[🚎ruby-2.4-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-2.4.yml
[🚎ruby-2.5-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-2.5.yml
[🚎ruby-2.6-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-2.6.yml
[🚎ruby-2.7-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-2.7.yml
[🚎ruby-3.0-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-3.0.yml
[🚎ruby-3.1-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-3.1.yml
[🚎ruby-3.2-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-3.2.yml
[🚎ruby-3.3-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-3.3.yml
[🚎ruby-3.4-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/ruby-3.4.yml
[🚎jruby-9.1-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby-9.1.yml
[🚎jruby-9.2-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby-9.2.yml
[🚎jruby-9.3-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby-9.3.yml
[🚎jruby-9.4-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby-9.4.yml
[🚎truby-22.3-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffleruby-22.3.yml
[🚎truby-23.0-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffleruby-23.0.yml
[🚎truby-23.1-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffleruby-23.1.yml
[🚎truby-24.2-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffleruby-24.2.yml
[🚎truby-25.0-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffleruby-25.0.yml
[🚎2-cov-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/coverage.yml
[🚎2-cov-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/coverage.yml/badge.svg
[🚎3-hd-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/heads.yml
[🚎3-hd-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/heads.yml/badge.svg
[🚎5-st-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/style.yml
[🚎5-st-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/style.yml/badge.svg
[🚎9-t-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffle.yml
[🚎9-t-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/truffle.yml/badge.svg
[🚎10-j-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby.yml
[🚎10-j-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/jruby.yml/badge.svg
[🚎11-c-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml
[🚎11-c-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/current.yml/badge.svg
[🚎12-crh-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/dep-heads.yml
[🚎12-crh-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/dep-heads.yml/badge.svg
[🚎13-🔒️-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/locked_deps.yml
[🚎13-🔒️-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/locked_deps.yml/badge.svg
[🚎14-🔓️-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/unlocked_deps.yml
[🚎14-🔓️-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/unlocked_deps.yml/badge.svg
[🚎15-🪪-wf]: https://github.com/kettle-rb/kettle-dev/actions/workflows/license-eye.yml
[🚎15-🪪-wfi]: https://github.com/kettle-rb/kettle-dev/actions/workflows/license-eye.yml/badge.svg
[💎ruby-2.3i]: https://img.shields.io/badge/Ruby-2.3-DF00CA?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-2.4i]: https://img.shields.io/badge/Ruby-2.4-DF00CA?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-2.5i]: https://img.shields.io/badge/Ruby-2.5-DF00CA?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-2.6i]: https://img.shields.io/badge/Ruby-2.6-DF00CA?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-2.7i]: https://img.shields.io/badge/Ruby-2.7-DF00CA?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.0i]: https://img.shields.io/badge/Ruby-3.0-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.1i]: https://img.shields.io/badge/Ruby-3.1-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.2i]: https://img.shields.io/badge/Ruby-3.2-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.3i]: https://img.shields.io/badge/Ruby-3.3-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-3.4i]: https://img.shields.io/badge/Ruby-3.4-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-4.0i]: https://img.shields.io/badge/Ruby-4.0-CC342D?style=for-the-badge&logo=ruby&logoColor=white
[💎ruby-c-i]: https://img.shields.io/badge/Ruby-current-CC342D?style=for-the-badge&logo=ruby&logoColor=green
[💎ruby-headi]: https://img.shields.io/badge/Ruby-HEAD-CC342D?style=for-the-badge&logo=ruby&logoColor=blue
[💎truby-22.3i]: https://img.shields.io/badge/Truffle_Ruby-22.3-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-23.0i]: https://img.shields.io/badge/Truffle_Ruby-23.0-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-23.1i]: https://img.shields.io/badge/Truffle_Ruby-23.1-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-24.2i]: https://img.shields.io/badge/Truffle_Ruby-24.2-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-25.0i]: https://img.shields.io/badge/Truffle_Ruby-25.0-34BCB1?style=for-the-badge&logo=ruby&logoColor=pink
[💎truby-c-i]: https://img.shields.io/badge/Truffle_Ruby-current-34BCB1?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-9.1i]: https://img.shields.io/badge/JRuby-9.1-FBE742?style=for-the-badge&logo=ruby&logoColor=red
[💎jruby-9.2i]: https://img.shields.io/badge/JRuby-9.2-FBE742?style=for-the-badge&logo=ruby&logoColor=red
[💎jruby-9.3i]: https://img.shields.io/badge/JRuby-9.3-FBE742?style=for-the-badge&logo=ruby&logoColor=red
[💎jruby-9.4i]: https://img.shields.io/badge/JRuby-9.4-FBE742?style=for-the-badge&logo=ruby&logoColor=red
[💎jruby-c-i]: https://img.shields.io/badge/JRuby-current-FBE742?style=for-the-badge&logo=ruby&logoColor=green
[💎jruby-headi]: https://img.shields.io/badge/JRuby-HEAD-FBE742?style=for-the-badge&logo=ruby&logoColor=blue
[🤝gh-issues]: https://github.com/kettle-rb/kettle-dev/issues
[🤝gh-pulls]: https://github.com/kettle-rb/kettle-dev/pulls
[🤝gl-issues]: https://gitlab.com/kettle-rb/kettle-dev/-/issues
[🤝gl-pulls]: https://gitlab.com/kettle-rb/kettle-dev/-/merge_requests
[🤝cb-issues]: https://codeberg.org/kettle-rb/kettle-dev/issues
[🤝cb-pulls]: https://codeberg.org/kettle-rb/kettle-dev/pulls
[🤝cb-donate]: https://donate.codeberg.org/
[🤝contributing]: CONTRIBUTING.md
[🏀codecov-g]: https://codecov.io/gh/kettle-rb/kettle-dev/graphs/tree.svg
[🖐contrib-rocks]: https://contrib.rocks
[🖐contributors]: https://github.com/kettle-rb/kettle-dev/graphs/contributors
[🖐contributors-img]: https://contrib.rocks/image?repo=kettle-rb/kettle-dev
[🚎contributors-gl]: https://gitlab.com/kettle-rb/kettle-dev/-/graphs/main
[🪇conduct]: CODE_OF_CONDUCT.md
[🪇conduct-img]: https://img.shields.io/badge/Contributor_Covenant-2.1-259D6C.svg
[📌pvc]: http://guides.rubygems.org/patterns/#pessimistic-version-constraint
[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-259D6C.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📌changelog]: CHANGELOG.md
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-34495e.svg?style=flat
[📌gitmoji]: https://gitmoji.dev
[📌gitmoji-img]: https://img.shields.io/badge/gitmoji_commits-%20%F0%9F%98%9C%20%F0%9F%98%8D-34495e.svg?style=flat-square
[🧮kloc]: https://www.youtube.com/watch?v=dQw4w9WgXcQ
[🧮kloc-img]: https://img.shields.io/badge/KLOC-5.053-FFDD67.svg?style=for-the-badge&logo=YouTube&logoColor=blue
[🔐security]: SECURITY.md
[🔐security-img]: https://img.shields.io/badge/security-policy-259D6C.svg?style=flat
[📄copyright-notice-explainer]: https://opensource.stackexchange.com/questions/5778/why-do-licenses-such-as-the-mit-license-specify-a-single-year
[📄license]: LICENSE.md
[📄license-ref]: AGPL-3.0-only.md
[📄license-img]: https://img.shields.io/badge/License-AGPL--3.0--only-259D6C.svg
[📄license-compat]: https://www.apache.org/legal/resolved.html#category-x
[📄license-compat-img]: https://img.shields.io/badge/Apache_Incompatible:_Category_X-%E2%9C%97-C0392B.svg?style=flat&logo=Apache
[📄ilo-declaration]: https://www.ilo.org/declaration/lang--en/index.htm
[📄ilo-declaration-img]: https://img.shields.io/badge/ILO_Fundamental_Principles-✓-259D6C.svg?style=flat
[🚎yard-current]: http://rubydoc.info/gems/kettle-dev
[🚎yard-head]: https://kettle-dev.galtzo.com
[💎stone_checksums]: https://github.com/galtzo-floss/stone_checksums
[💎SHA_checksums]: https://gitlab.com/kettle-rb/kettle-dev/-/tree/main/checksums
[💎rlts]: https://github.com/rubocop-lts/rubocop-lts
[💎rlts-img]: https://img.shields.io/badge/code_style_&_linting-rubocop--lts-34495e.svg?plastic&logo=ruby&logoColor=white
[💎appraisal2]: https://github.com/appraisal-rb/appraisal2
[💎appraisal2-img]: https://img.shields.io/badge/appraised_by-appraisal2-34495e.svg?plastic&logo=ruby&logoColor=white
[💎d-in-dvcs]: https://railsbling.com/posts/dvcs/put_the_d_in_dvcs/
