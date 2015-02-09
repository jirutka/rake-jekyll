require 'rake/tasklib'
require 'tmpdir'

module Rake::Jekyll
  ##
  # This task builds the Jekyll site and deploys it to a remote Git repository.
  class GitDeployTask < ::Rake::TaskLib

    ##
    # @private
    # Functions that wraps calls to +git+ command.
    module GitCommands

      def any_changes?
        ! `git status --porcelain`.empty?
      end

      def clone_repo(url)
        sh "git clone '#{url}' ."
      end

      def checkout_remote_branch(name)
        sh "git checkout --track #{name}"
      end

      def commit_all(message, author = '', date = '')
        opts = [ "--message='#{message}'" ]
        opts << "--author='#{author}'" unless author.empty?
        opts << "--date='#{date}'" unless date.empty?

        sh "git add --all && git commit #{opts.join(' ')}"
      end

      def config_set?(key)
        ! `git config --get #{key}`.empty?
      end

      def config_user_set(name_email)
        name, email = parse_name_email(name_email)
        sh "git config --local user.name '#{name}'"
        sh "git config --local user.email '#{email}'"
      end

      def create_orphan_branch(name)
        sh "git checkout --orphan #{name}"
        sh 'git rm -rf . &>/dev/null || true'
      end

      # @return [String] name of the current active branch.
      def current_branch
        `git symbolic-ref --short -q HEAD`.strip
      end

      def push(remote_url, branch)
        sh "git push -q #{remote_url} #{branch}:#{branch}"
      end

      private

      def parse_name_email(str)
        if matched = str.match(/^([^<]*)(?:<([^>]*)>)?$/)
          matched[1..2].map do |val|
            val.strip.empty? ? nil : val.strip if val
          end
        end
      end
    end

    include GitCommands

    ##
    # @private
    # Defines attribute accessor with optional default value.
    # When attribute's value is a +Proc+ with arity 0, then the attribute
    # reader calls it and returns the result.
    #
    # @param attr_name [#to_s] name of the attribute to define.
    # @param default_value [Object] the default value (optional).
    # @yield When the block is given, then it's used as a default value.
    #   It takes precedence over +default_value+.
    def self.callable_attr(attr_name, default_value = nil, &default_block)
      var_name = "@#{attr_name}".sub('?', '').to_sym

      define_method attr_name do
        value = instance_variable_get(var_name)
        if value.nil? && default_block
          do_in_working_dir &default_block
        elsif value.nil?
          default_value
        elsif value.is_a?(Proc) && value.arity.zero?
          do_in_working_dir &value
        else
          value
        end
      end

      attr_writer attr_name.to_s.sub('?', '')
    end

    # @return [#to_sym] name of the task.
    attr_accessor :name

    # @return [#to_s] description of the task.
    attr_accessor :description

    ##
    # @!attribute author
    # Overrides the _author_ of the commit being created in {#deploy_branch}.
    # Defaults to author of the HEAD in the current (i.e. source) branch.
    #
    # @return [String, Proc] author name and email in the standard mail format,
    #   e.g. Kevin Flynn <kevin@flynn.com>, or empty string to not override.
    #
    callable_attr :author do
      `git log -n 1 --format='%aN <%aE>'`.strip
    end

    ##
    # @!attribute author_date
    # Overrides the _author date_ of the commit being created in
    # {#deploy_branch}. Defaults to date of the HEAD in the current
    # (i.e. source) branch.
    #
    # @return [String, Proc] date in any format supported by git (i.e. Git
    #   internal format, RFC 2822, or RFC 8601).
    #
    callable_attr :author_date do
      `git log -n 1 --format='%aD'`.strip
    end

    ##
    # @!attribute commit_message
    # @return [String, Proc] the commit message. Defaults to +Built from {REV}+,
    #   where +{REV}+ is hash of the HEAD in the current (i.e. source) branch.
    callable_attr :commit_message do
      hash = `git rev-parse --short HEAD`.strip
      "Built from #{hash}"
    end

    ##
    # @!attribute committer
    # Defines the default _committer_ to be used when the +user.name+ is not
    # set in git config and/or {#override_committer?} is +true+.
    #
    # @return [String, Proc] author name and email in the standard mail format,
    #   e.g. Kevin Flynn <kevin@flynn.com>. (default: +Jekyll+).
    #
    callable_attr :committer, 'Jekyll'

    ##
    # @!attribute deploy_branch
    # Defines name of the remote branch to deploy the built site into.
    # If the remote branch doesn't exist yet, then it's automatically created
    # as an orphan branch.
    #
    # @return [String, Proc] name of the remote branch (default: +gh-pages+).
    #
    callable_attr :deploy_branch, 'gh-pages'

    ##
    # @!attribute jekyll_build
    # Defines a function that executes Jekyll to build the site.
    # Defaults to:
    #   Rake.sh "bundle exec jekyll build --destination #{dest_dir}"
    #
    # @return [Proc] a Proc that accepts one argument; the destination
    #   directory to generate the site into.
    #
    callable_attr :jekyll_build, ->(dest_dir) {
      Rake.sh "bundle exec jekyll build --destination #{dest_dir}"
    }

    ##
    # @!attribute override_committer?
    # @return [Boolean, Proc] +true+ to always use {#committer}, +false+ to use
    #   the default committer (configured in git) when available.
    callable_attr :override_committer?, false

    ##
    # @!attribute remote_url
    # @return [String, Proc] URL of the remote git repository to fetch and push
    #   the built site into. The default is to use URL of the +origin+ remote,
    #   replace +git:+ schema with +https:+ and add environment variable
    #   +GH_TOKEN+ as an userinfo (if exists).
    callable_attr :remote_url do
      `git config remote.origin.url`.strip.gsub(/^git:/, 'https:').tap do |url|
        url.gsub!(%r{^https://}, "https://#{ENV['GH_TOKEN']}@") if ENV.key? 'GH_TOKEN'
      end
    end

    ##
    # @!attribute [w] skip_commit
    # Whether to skip the commit and push phase.
    # Default is to return +true+ when env variable +TRAVIS_PULL_REQUEST+
    # is an integer value greater than 0 or +SKIP_COMMIT+ represents truthy
    # (i.e. contains yes, y, true, or 1).
    #
    # @return [Boolean, Proc]
    #
    callable_attr :skip_commit? do
      ENV['TRAVIS_PULL_REQUEST'].to_i > 0 ||
        %w[yes y true 1].include?(ENV['SKIP_COMMIT'].to_s.downcase)
    end


    ##
    # @param name [#to_sym] name of the task to define.
    # @yield The block to configure this task.
    def initialize(name = :deploy)
      @name = name
      @description = 'Generate the site and push changes to remote repository'
      @working_dir = Dir.pwd

      yield self if block_given?

      define_task!
    end

    private

    def define_task!
      desc description.to_s

      task name.to_sym do
        @working_dir = Dir.pwd

        Dir.mktmpdir do |temp_dir|
          Dir.chdir temp_dir do
            clone_repo remote_url

            if current_branch != deploy_branch
              begin
                checkout_remote_branch "origin/#{deploy_branch}"
              rescue RuntimeError
                puts "\nBranch #{deploy_branch} doesn't exist yet, initializing..."
                create_orphan_branch deploy_branch
              end
            end
          end

          puts "\nRunning Jekyll..."
          jekyll_build[temp_dir]

          Dir.chdir temp_dir do
            unless any_changes?
              puts 'Nothing to commit.'; next
            end

            if skip_commit?
              puts 'Skipping commit.'; next
            end

            if override_committer? || !config_set?('user.name')
              config_user_set committer
            end

            commit_all commit_message, author, author_date
            push remote_url, deploy_branch
          end
        end
      end
    end

    def do_in_working_dir
      Dir.chdir @working_dir do
        yield
      end
    end
  end
end
