# Load from a "rakelib" directory is automatic!
# Adding a custom directory of tasks as a "rakelib" directory makes them available.
#
# This file is loaded by Kettle::Dev.install_tasks to register the
# gem-provided Rake tasks with the host application's Rake context.
abs_path = File.expand_path(__dir__)
rakelib = "#{abs_path}/rakelib"
Rake.add_rakelib(rakelib)
