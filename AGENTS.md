# AGENTS.md - kettle-dev Development Guide

## 🎯 Project Overview

`kettle-dev` is a **meta tool from kettle-rb to streamline development and testing** of RubyGem projects. It acts as a shim dependency, pulling in many other dependencies, to give you OOTB productivity. It configures Rake tasks, manages gem templating, handles releases, and automates CI workflows.

**Repository**: https://github.com/kettle-rb/kettle-dev
**Current Version**: 1.2.5
**Required Ruby**: >= 2.3.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

**CRITICAL**: AI agents can reliably read terminal output when commands run in the background and the output is polled afterward. However, each terminal command should be treated as a fresh shell with no shared state.

**Use this pattern**:
1. Run commands with background execution enabled.
2. Fetch the output afterward.
3. Make every command self-contained — do **not** rely on a previous `cd`, `export`, alias, or shell function.

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment now lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. That interactive trust screen can masquerade as missing terminal output, so commands may appear hung or silent until you handle it.

**Recovery rule**: If a `mise exec` command in this repo goes silent, appears hung, or terminal polling stops returning useful output, assume `mise trust` is needed first and recover with:

```bash
mise trust -C /home/pboling/src/kettle-rb/kettle-dev
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace, silent `mise` commands are usually a trust problem.

```bash
mise trust -C /home/pboling/src/kettle-rb/kettle-dev
```

✅ **CORRECT** — Run self-contained commands with `mise exec`:
```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

✅ **CORRECT** — If you need shell syntax first, load the environment in the same command:
```bash
eval "$(mise env -C /home/pboling/src/kettle-rb/kettle-dev -s bash)" && bundle exec rspec
```

❌ **WRONG** — Do not rely on a previous command changing directories:
```bash
cd /home/pboling/src/kettle-rb/kettle-dev
bundle exec rspec
```

❌ **WRONG** — A chained `cd` does not give directory-change hooks time to update the environment:
```bash
cd /home/pboling/src/kettle-rb/kettle-dev && bundle exec rspec
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
- Git operations that require interaction
- Commands that actually need to execute (not just gather info)

### Workspace layout

This repo is a sibling project inside the `/home/pboling/src/kettle-rb` workspace, not a vendored dependency under another repo.

### NEVER Pipe Test Commands Through head/tail

❌ **ABSOLUTELY FORBIDDEN**:
```bash
bundle exec rspec 2>&1 | tail -50
```

✅ **CORRECT** — Run the plain command and read the full output afterward:
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

This repo is a sibling project inside the `/home/pboling/src/kettle-rb` workspace, not a vendored dependency under another repo.

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

## 🔧 Development Workflows

### Running Tests

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rspec
```

Single file (disable coverage threshold):
```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/kettle/dev/release_cli_spec.rb
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bin/rake coverage
```

**Key ENV variables** (set in `mise.toml`, with local overrides in `.env.local`):
- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE=92` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH=76` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rake reek
mise exec -C /home/pboling/src/kettle-rb/kettle-dev -- bundle exec rake rubocop_gradual
```

## 📝 Project Conventions

### Freeze Block Preservation

kettle-dev templates support freeze blocks to preserve custom code during template updates:

```ruby
# kettle-dev:freeze
# ... custom code preserved across template runs ...
# kettle-dev:unfreeze
```

### Modular Gemfile Architecture

Gemfiles are split into modular components under `gemfiles/modular/`. Each component handles a specific concern (coverage, style, debug, etc.). The `style.gemfile.example` uses token replacement for Ruby-version-specific RuboCop constraints:

- `{RUBOCOP|LTS|CONSTRAINT}` — Replaced with the appropriate `rubocop-lts` version constraint
- `{RUBOCOP|RUBY|GEM}` — Replaced with the appropriate `rubocop-ruby*` gem name

### Template Merging Strategy

kettle-dev uses AST-based merging (via `prism-merge`, `markly-merge`, etc.) to intelligently merge template files with existing project files, preserving custom modifications while updating templated content.

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

## 🚫 Common Pitfalls

1. **NEVER add backward compatibility** — No shims, aliases, or deprecation layers.
2. **NEVER expect `cd` to persist** — Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
3. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.
4. **Terminal commands do not share shell state** — Previous `cd`, `export`, aliases, and functions are not available to the next command.
5. **Use `tmp/` for temporary files** — Never use `/tmp` or other system directories.
6. **`vendor/` is for local development only** — Does not exist in CI.
