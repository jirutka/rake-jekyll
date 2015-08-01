require 'rake-jekyll'

Rake::Jekyll::GitDeployTask.new(:deploy) do |t|

  t.committer = 'Travis'
  t.deploy_branch = 'test-target'

  t.jekyll_build = ->(dest_dir) {
    sh "date > #{dest_dir}/i_was_here"
  }
end
