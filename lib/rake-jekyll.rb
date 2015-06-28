module Rake
  module Jekyll
    BIN_DIR = File.expand_path('../bin', __dir__)
  end
end

require 'rake-jekyll/version'
require 'rake-jekyll/git_deploy_task'
