# --- CI helpers ---
namespace :ci do
  desc "Run 'act' with a selected workflow. Usage: rake ci:act[loc], ci:act[locked_deps], ci:act[locked_deps.yml], or rake ci:act (interactive)"
  task :act, [:opt] do |_t, args|
    require "kettle/dev/tasks/ci_task"
    Kettle::Dev::Tasks::CITask.act(args[:opt])
  end
end
