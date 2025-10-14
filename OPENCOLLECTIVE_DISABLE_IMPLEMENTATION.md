# Open Collective Disable Implementation

## Summary

This document describes the implementation for handling scenarios when `OPENCOLLECTIVE_HANDLE` is set to a falsey value.

## Changes Made

### 1. Created `.no-osc.example` Template Files

Created the following template files that exclude Open Collective references:

- **`.github/FUNDING.yml.no-osc.example`** - FUNDING.yml without the `open_collective` line
- **`README.md.no-osc.example`** - Already existed (created by user)
- **`FUNDING.md.no-osc.example`** - Already existed (created by user)

### 2. Modified `lib/kettle/dev/template_helpers.rb`

Added three new helper methods:

#### `opencollective_disabled?`
Returns `true` when `OPENCOLLECTIVE_HANDLE` or `FUNDING_ORG` environment variables are explicitly set to falsey values (`false`, `no`, or `0`).

```ruby
def opencollective_disabled?
  oc_handle = ENV["OPENCOLLECTIVE_HANDLE"]
  funding_org = ENV["FUNDING_ORG"]

  # Check if either variable is explicitly set to false
  [oc_handle, funding_org].any? do |val|
    val && val.to_s.strip.match(Kettle::Dev::ENV_FALSE_RE)
  end
end
```

**Note**: This method is used centrally by both `TemplateHelpers` and `GemSpecReader` to ensure consistent behavior across the codebase.

#### `prefer_example_with_osc_check(src_path)`
Extends the existing `prefer_example` method to check for `.no-osc.example` variants when Open Collective is disabled.

- When `opencollective_disabled?` returns `true`, it first looks for a `.no-osc.example` variant
- Falls back to the standard `prefer_example` behavior if no `.no-osc.example` file exists

#### `skip_for_disabled_opencollective?(relative_path)`
Determines if a file should be skipped during the template process when Open Collective is disabled.

Returns `true` for these files when `opencollective_disabled?` is `true`:
- `.opencollective.yml`
- `.github/workflows/opencollective.yml`

### 3. Modified `lib/kettle/dev/tasks/template_task.rb`

Updated the template task to use the new helpers:

1. **In the `.github` files section**:
   - Replaced `helpers.prefer_example(orig_src)` with `helpers.prefer_example_with_osc_check(orig_src)`
   - Added check to skip opencollective-specific workflow files

2. **In the root files section**:
   - Replaced `helpers.prefer_example(...)` with `helpers.prefer_example_with_osc_check(...)`
   - Added check at the start of `files_to_copy.each` loop to skip opencollective files

### 4. Modified `lib/kettle/dev/gem_spec_reader.rb`

Updated the `funding_org` detection logic to use the centralized `TemplateHelpers.opencollective_disabled?` method:

- **Removed** the inline check for `ENV["FUNDING_ORG"] == "false"`
- **Replaced** with a call to `TemplateHelpers.opencollective_disabled?` at the beginning of the funding_org detection block
- This ensures consistent behavior: when Open Collective is disabled via any supported method (`OPENCOLLECTIVE_HANDLE=false`, `FUNDING_ORG=false`, etc.), the `funding_org` will be set to `nil`

**Precedence for funding_org detection:**
1. If `TemplateHelpers.opencollective_disabled?` returns `true` → `funding_org = nil`
2. Otherwise, if `ENV["FUNDING_ORG"]` is set and non-empty → use that value
3. Otherwise, attempt to read from `.opencollective.yml` via `OpenCollectiveConfig.handle`
4. If all above fail → `funding_org = nil` with a warning

## Usage

### To Disable Open Collective

Set one of these environment variables to a falsey value:

```bash
# Option 1: Using OPENCOLLECTIVE_HANDLE
OPENCOLLECTIVE_HANDLE=false bundle exec rake kettle:dev:template

# Option 2: Using FUNDING_ORG
FUNDING_ORG=false bundle exec rake kettle:dev:template

# Other accepted falsey values: no, 0 (case-insensitive)
OPENCOLLECTIVE_HANDLE=no bundle exec rake kettle:dev:template
OPENCOLLECTIVE_HANDLE=0 bundle exec rake kettle:dev:template
```

### Expected Behavior

When Open Collective is disabled, the template process will:

1. **Skip copying** `.opencollective.yml`
2. **Skip copying** `.github/workflows/opencollective.yml`
3. **Use `.no-osc.example` variants** for:
   - `README.md` → Uses `README.md.no-osc.example`
   - `FUNDING.md` → Uses `FUNDING.md.no-osc.example`
   - `.github/FUNDING.yml` → Uses `.github/FUNDING.yml.no-osc.example`

4. **Display skip messages** like:
   ```
   Skipping .opencollective.yml (Open Collective disabled)
   Skipping .github/workflows/opencollective.yml (Open Collective disabled)
   ```

## File Precedence Logic

For any file being templated, the system now follows this precedence:

1. If `opencollective_disabled?` is `true`:
   - First, check for `filename.no-osc.example`
   - If not found, fall through to normal logic

2. Normal logic (when OC not disabled or no `.no-osc.example` exists):
   - Check for `filename.example`
   - Fall back to `filename`

## Testing Recommendations

To test the implementation:

1. **Test with Open Collective enabled** (default behavior):
   ```bash
   bundle exec rake kettle:dev:template
   ```
   Should use regular `.example` files and copy all opencollective files.

2. **Test with Open Collective disabled**:
   ```bash
   OPENCOLLECTIVE_HANDLE=false bundle exec rake kettle:dev:template
   ```
   Should skip opencollective files and use `.no-osc.example` variants.

3. **Verify file content**:
   - Check that `.github/FUNDING.yml` has no `open_collective:` line when disabled
   - Check that `README.md` has no opencollective badges/links when disabled
   - Check that `FUNDING.md` has no opencollective references when disabled

## Automated Tests

A comprehensive test suite has been added in `spec/kettle/dev/opencollective_disable_spec.rb` that covers:

### TemplateHelpers Tests

1. **`opencollective_disabled?` method**:
   - Tests all falsey values: `false`, `False`, `FALSE`, `no`, `NO`, `0`
   - Tests both `OPENCOLLECTIVE_HANDLE` and `FUNDING_ORG` environment variables
   - Tests behavior when variables are unset, empty, or set to valid org names
   - Verifies that either variable being falsey triggers the disabled state

2. **`skip_for_disabled_opencollective?` method**:
   - Verifies that `.opencollective.yml` is skipped when disabled
   - Verifies that `.github/workflows/opencollective.yml` is skipped when disabled
   - Ensures other files (README.md, FUNDING.md, etc.) are not skipped
   - Tests behavior when Open Collective is enabled

3. **`prefer_example_with_osc_check` method**:
   - Tests preference for `.no-osc.example` files when OC is disabled
   - Tests fallback to `.example` when `.no-osc.example` doesn't exist
   - Tests fallback to original file when neither variant exists
   - Handles paths that already end with `.example`
   - Tests normal behavior (prefers `.example`) when OC is enabled

### GemSpecReader Tests

1. **`funding_org` detection with OPENCOLLECTIVE_HANDLE=false**:
   - Verifies `funding_org` is set to `nil` when disabled
   - Tests all falsey values: `false`, `no`, `0`
   - Tests both `OPENCOLLECTIVE_HANDLE` and `FUNDING_ORG` variables
   - Ensures `.opencollective.yml` is ignored when OC is disabled

2. **`funding_org` detection with OPENCOLLECTIVE_HANDLE enabled**:
   - Tests using `OPENCOLLECTIVE_HANDLE` value when set
   - Tests using `FUNDING_ORG` value when set
   - Tests reading from `.opencollective.yml` when env vars are unset

### Running the Tests

Run the Open Collective disable tests:
```bash
bundle exec rspec spec/kettle/dev/opencollective_disable_spec.rb
```

Run all tests:
```bash
bundle exec rspec
```

Run with documentation format for detailed output:
```bash
bundle exec rspec spec/kettle/dev/opencollective_disable_spec.rb --format documentation
```
