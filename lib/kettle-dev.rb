# rubocop:disable Naming/FileName# USAGE:
# In your `spec/spec_helper.rb`,
# just prior to loading the library under test:
#
#   require "kettle-dev"
#
# In your `Rakefile` file:
#
#   require "kettle/dev"
#

# For technical reasons, if we move to Zeitwerk, this cannot be require_relative.
#   See: https://github.com/fxn/zeitwerk#for_gem_extension
# Hook for other libraries to load this library (e.g. via bundler)
#
# @example In your spec/spec_helper.rb
#   require "kettle-dev" # or require "kettle/dev"
# @example In your Rakefile
#   require "kettle-dev" # or require "kettle/dev"
require "kettle/dev"
# rubocop:enable Naming/FileName
