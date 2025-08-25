# frozen_string_literal: true

namespace :kettle do
  namespace :dev do
    desc "Template kettle-dev files into the current project"
    task :template do
      Kettle::Dev::Tasks::TemplateTask.run
    end
  end
end
