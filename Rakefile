# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

task :steep do
  sh "bundle exec steep check"
end

task default: %i[test standard steep]
