# AGENTS.md - Development Guide

## 🎯 Project Overview

`kettle-dev` is a **meta tool from kettle-rb to streamline development and testing** of RubyGem projects. It acts as a shim dependency, pulling in many other dependencies, to give you OOTB productivity. It configures Rake tasks, manages gem templating, handles releases, and automates CI workflows.

This project is a **RubyGem** managed with the [kettle-rb](https://github.com/kettle-rb) toolchain.

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

**Minimum Supported Ruby**: See the gemspec `required_ruby_version` constraint.
**Local Development Ruby**: See `.tool-versions` for the version used in local development (typically the latest stable Ruby).

**Use this pattern**:

- Uses `kettle-test` for RSpec helpers (stubbed_env, block_is_expected, silent_stream, timecop)
- Uses `Dir.mktmpdir` for isolated filesystem tests
- Spec helper is loaded by `.rspec` — never add `require "spec_helper"` to spec files

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. Until that trust step is handled, commands can appear hung or produce no output, which can look like terminal access is broken.

**Recovery rule**: If a `mise exec` command goes silent or appears hung, assume `mise trust` is the first thing to check. Recover by running:

```bash
mise trust -C /home/pboling/src/kettle-rb/kettle-dev
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

```bash
mise trust -C /path/to/project
mise exec -C /path/to/project -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace pattern, silent `mise` commands are usually a trust problem first.

```bash
mise trust -C /home/pboling/src/kettle-rb/kettle-dev
```

✅ **CORRECT** — Run self-contained commands with `mise exec`:
```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

✅ **CORRECT** — If you need shell syntax first, load the environment in the same command:
```bash
eval "$(mise env -C /home/pboling/src/kettle-rb/kettle-dev -s bash)" && bundle exec rspec
```

```bash
eval "$(mise env -C /path/to/project -s bash)" && bundle exec rspec
```

❌ **WRONG** — Do not rely on a previous command changing directories:
```bash
cd /home/pboling/src/kettle-rb/kettle-dev
bundle exec rspec
```

```bash
cd /path/to/project
bundle exec rspec
```

❌ **WRONG** — A chained `cd` does not give directory-change hooks time to update the environment:
```bash
cd /home/pboling/src/kettle-rb/kettle-dev && bundle exec rspec
```

```bash
cd /path/to/project && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

✅ **PREFERRED** — Use internal tools:

- `grep_search` instead of `grep` command
- `file_search` instead of `find` command
- `read_file` instead of `cat` command
- `list_dir` instead of `ls` command
- `replace_string_in_file` or `create_file` instead of `sed` / manual editing

❌ **AVOID** when possible:

- `run_in_terminal` for information gathering

Only use terminal for:

- Running tests (`bundle exec rspec`)
- Installing dependencies (`bundle install`)
- Simple commands that do not require much shell escaping
- Running scripts (prefer writing a script over a complicated command with shell escaping)

### Workspace layout

### Toolchain Dependencies

This gem is part of the **kettle-rb** ecosystem. Key development tools:

### NEVER Pipe Test Commands Through head/tail

❌ **ABSOLUTELY FORBIDDEN**:
```bash
bundle exec rspec 2>&1 | tail -50
```

When you do run tests, keep the full output visible so you can inspect failures completely.

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

## 🏗️ Architecture

### What kettle-dev Provides

- **`Kettle::Dev::ReleaseCLI`** — Full gem release automation (changelog, version bumping, GitHub releases, CI monitoring)
- **`Kettle::Dev::PreReleaseCLI`** — Pre-release checks and validation
- **`Kettle::Dev::SetupCLI`** — Project scaffolding and template setup (`kettle-dev-setup`)
- **`Kettle::Dev::TemplateHelpers`** — AST-based file merging for template updates (uses `prism-merge`, `markly-merge`, etc.)
- **`Kettle::Dev::SourceMerger`** — Smart source merging with freeze block preservation
- **`Kettle::Dev::ModularGemfiles`** — Modular Gemfile management (style, coverage, debug, etc.)
- **`Kettle::Dev::ChangelogCLI`** — Automated changelog generation
- **`Kettle::Dev::DvcsCLI`** — DVCS (git) workflow automation
- **`Kettle::Dev::CommitMsg`** — Git commit message validation
- **`Kettle::Dev::CIHelpers`** — CI platform detection and helpers
- **`Kettle::Dev::CIMonitor`** — GitHub Actions workflow monitoring
- **`Kettle::Dev::PrismUtils`** / **`PrismGemspec`** / **`PrismGemfile`** / **`PrismAppraisals`** — AST-based Ruby file analysis and manipulation
- **`Kettle::Dev::GemSpecReader`** — Gemspec introspection
- **`Kettle::Dev::Versioning`** — Version management utilities
- **`Kettle::Dev::ReadmeBackers`** — Open Collective backer management
- **`Kettle::Dev::GitAdapter`** — Git interaction abstraction (shells out or uses `git` gem)
- **`Kettle::Dev::ExitAdapter`** — Testable exit/abort behavior

### Executables

| Executable | Purpose |
|-----------|---------|
| `kettle-release` | Full gem release workflow |
| `kettle-pre-release` | Pre-release validation |
| `kettle-changelog` | Changelog generation |
| `kettle-dev-setup` | Project scaffolding |
| `kettle-dvcs` | DVCS workflow |
| `kettle-commit-msg` | Commit message validation |
| `kettle-readme-backers` | Backer list management |
| `kettle-gh-release` | GitHub release creation |
| `kettle-check-eof` | EOF newline validation |

### Key Dependencies

| Gem | Role |
|-----|------|
| `kettle-test` (~> 1.0) | Test infrastructure (dev dependency) |
| `ruby-progressbar` (~> 1.13) | Progress display during releases |
| `stone_checksums` (~> 1.0) | Gem checksum generation |
| `prism-merge` | AST-based Ruby file merging (via kettle-jem or direct) |
| `markly-merge` | Markdown file merging (via kettle-jem or direct) |

### Workspace layout

### Dependency Tags

Use dependency tags to conditionally skip tests when optional dependencies are not available:

| Tool | Purpose |
|------|---------|
| `kettle-dev` | Development dependency: Rake tasks, release tooling, CI helpers |
| `kettle-test` | Test infrastructure: RSpec helpers, stubbed_env, timecop |
| `kettle-jem` | Template management and gem scaffolding |

### Executables (from kettle-dev)

| Executable | Purpose |
|-----------|---------|
| `kettle-release` | Full gem release workflow |
| `kettle-pre-release` | Pre-release validation |
| `kettle-changelog` | Changelog generation |
| `kettle-dvcs` | DVCS (git) workflow automation |
| `kettle-commit-msg` | Commit message validation |
| `kettle-check-eof` | EOF newline validation |

## 📁 Project Structure

```
lib/kettle/dev/
├── changelog_cli.rb           # Changelog generation CLI
├── ci_helpers.rb              # CI platform detection
├── ci_monitor.rb              # GitHub Actions monitoring
├── commit_msg.rb              # Commit message validation
├── dvcs_cli.rb                # DVCS workflow CLI
├── exit_adapter.rb            # Testable exit/abort
├── gem_spec_reader.rb         # Gemspec introspection
├── git_adapter.rb             # Git interaction abstraction
├── git_commit_footer.rb       # Commit footer formatting
├── input_adapter.rb           # User input abstraction
├── modular_gemfiles.rb        # Modular Gemfile management
├── open_collective_config.rb  # Open Collective configuration
├── pre_release_cli.rb         # Pre-release validation
├── prism_appraisals.rb        # Appraisals file analysis
├── prism_gemfile.rb           # Gemfile AST analysis
├── prism_gemspec.rb           # Gemspec AST analysis
├── prism_utils.rb             # Shared Prism utilities
├── rakelib/                   # Rake task definitions
├── readme_backers.rb          # Backer list management
├── release_cli.rb             # Full release workflow (~1100 lines)
├── setup_cli.rb               # Project setup/scaffolding
├── source_merger.rb           # Smart source merging
├── tasks/                     # CI, install, template tasks
├── tasks.rb                   # Task loader
├── template_helpers.rb        # Template merging helpers
├── version.rb                 # Version constant
└── versioning.rb              # Version management

gemfiles/modular/
├── coverage.gemfile           # Coverage dependencies
├── debug.gemfile              # Debug dependencies
├── documentation.gemfile      # Yard/documentation
├── optional.gemfile[.example] # Optional dependencies
├── rspec.gemfile              # RSpec testing
├── runtime_heads.gemfile      # HEAD tracking
├── style.gemfile[.example]    # RuboCop/style checking
├── templating.gemfile         # Template merging dependencies
├── x_std_libs.gemfile         # Extracted stdlib gems
├── benchmark/                 # Per-Ruby-version benchmark gemfiles
├── erb/                       # Per-Ruby-version erb gemfiles
├── mutex_m/                   # Per-Ruby-version mutex_m gemfiles
├── stringio/                  # Per-Ruby-version stringio gemfiles
└── x_std_libs/                # Per-Ruby-version std lib gemfiles

exe/
├── kettle-changelog
├── kettle-check-eof
├── kettle-commit-msg
├── kettle-dev-setup
├── kettle-dvcs
├── kettle-gh-release
├── kettle-pre-release
├── kettle-readme-backers
└── kettle-release
```

```
lib/
├── <gem_namespace>/           # Main library code
│   └── version.rb             # Version constant (managed by kettle-release)
spec/
├── fixtures/                  # Test fixture files (NOT auto-loaded)
├── support/
│   ├── classes/               # Helper classes for specs
│   └── shared_contexts/       # Shared RSpec contexts
├── spec_helper.rb             # RSpec configuration (loaded by .rspec)
gemfiles/
├── modular/                   # Modular Gemfile components
│   ├── coverage.gemfile       # SimpleCov dependencies
│   ├── debug.gemfile          # Debugging tools
│   ├── documentation.gemfile  # YARD/documentation
│   ├── optional.gemfile       # Optional dependencies
│   ├── rspec.gemfile          # RSpec testing
│   ├── style.gemfile          # RuboCop/linting
│   └── x_std_libs.gemfile     # Extracted stdlib gems
├── ruby_*.gemfile             # Per-Ruby-version Appraisal Gemfiles
└── Appraisal.root.gemfile     # Root Gemfile for Appraisal builds
.git-hooks/
├── commit-msg                 # Commit message validation hook
├── prepare-commit-msg         # Commit message preparation
├── commit-subjects-goalie.txt # Commit subject prefix filters
└── footer-template.erb.txt    # Commit footer ERB template
```

## 🔧 Development Workflows

### Running Tests

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

Full suite spec runs:

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

For single file, targeted, or partial spec runs the coverage threshold **must** be disabled.
Use the `K_SOUP_COV_MIN_HARD=false` environment variable to disable hard failure:

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/kettle/dev/release_cli_spec.rb
```

```bash
mise exec -C /path/to/project -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/path/to/spec.rb
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bin/rake coverage
```

```bash
mise exec -C /path/to/project -- bin/rake coverage
mise exec -C /path/to/project -- bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `mise.toml`, with local overrides in `.env.local`):

- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rake reek
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rake rubocop_gradual
```

```bash
mise exec -C /path/to/project -- bundle exec rake reek
mise exec -C /path/to/project -- bundle exec rubocop-gradual
```

### Releasing

```bash
bin/kettle-pre-release    # Validate everything before release
bin/kettle-release        # Full release workflow
```

## 📝 Project Conventions

### Freeze Block Preservation

Template updates preserve custom code wrapped in freeze blocks:

```ruby
# kettle-dev:freeze
# ... custom code preserved across template runs ...
# kettle-dev:unfreeze
```

```ruby
# kettle-jem:freeze
# ... custom code preserved across template runs ...
# kettle-jem:unfreeze
```

### Modular Gemfile Architecture

Gemfiles are split into modular components under `gemfiles/modular/`. Each component handles a specific concern (coverage, style, debug, etc.). The main `Gemfile` loads these modular components via `eval_gemfile`.

- `{RUBOCOP|LTS|CONSTRAINT}` — Replaced with the appropriate `rubocop-lts` version constraint
- `{RUBOCOP|RUBY|GEM}` — Replaced with the appropriate `rubocop-ruby*` gem name

### Template Merging Strategy

### Running Commands

Always make commands self-contained. Use `mise exec -C /home/pboling/src/kettle-rb/prism-merge -- ...` so the command gets the project environment in the same invocation.
If the command is complicated write a script in local tmp/ and then run the script.

### Forward Compatibility with `**options`

**CRITICAL**: All constructors and public API methods that accept keyword arguments MUST include `**options` as the final parameter for forward compatibility.

## 🧪 Testing Patterns

### Test Infrastructure

- Uses `kettle-test` for RSpec helpers (stubbed_env, block_is_expected, silent_stream, timecop)
- Uses `MockSystemExit` for testing abort behavior
- Uses `Dir.mktmpdir` for isolated filesystem tests
- Git operations are mocked via `GitAdapter` and `CIHelpers` stubs

### Environment Variable Helpers

```ruby
before do
  stub_env("MY_ENV_VAR" => "value")
end

before do
  hide_env("HOME", "USER")
end
```

## 🔍 Critical Files

| File | Purpose |
|------|---------|
| `lib/kettle/dev/release_cli.rb` | Full release workflow (~1100 lines) |
| `lib/kettle/dev/template_helpers.rb` | AST-based template merging |
| `lib/kettle/dev/source_merger.rb` | Smart source merging with freeze blocks |
| `lib/kettle/dev/modular_gemfiles.rb` | Modular Gemfile sync logic |
| `lib/kettle/dev/setup_cli.rb` | Project scaffolding |
| `lib/kettle/dev/prism_gemfile.rb` | Gemfile AST analysis |
| `lib/kettle/dev/prism_gemspec.rb` | Gemspec AST analysis |
| `lib/kettle/dev/ci_monitor.rb` | GitHub Actions monitoring |
| `gemfiles/modular/style.gemfile.example` | Style template with token replacement |
| `Rakefile.example` | Template Rakefile for projects |
| `mise.toml` | Shared development environment variables and local `.env.local` loading |

```ruby
RSpec.describe SomeClass, :prism_merge do
  # Skipped if prism-merge is not available
end
```

## 🚫 Common Pitfalls

1. **NEVER add backward compatibility** — No shims, aliases, or deprecation layers.
2. **NEVER expect `cd` to persist** — Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
3. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.
4. **Terminal commands do not share shell state** — Previous `cd`, `export`, aliases, and functions are not available to the next command.
5. **Use `tmp/` for temporary files** — Never use `/tmp` or other system directories.
6. **`vendor/` is for local development only** — Does not exist in CI.

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.

1. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.
