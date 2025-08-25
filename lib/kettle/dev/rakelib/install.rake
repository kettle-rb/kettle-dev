# frozen_string_literal: true

namespace :kettle do
  namespace :dev do
    desc "Install kettle-dev GitHub automation and setup hints into the current project"
    task :install do
      Kettle::Dev::Tasks::InstallTask.run
    end
  end
end
