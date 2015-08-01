require 'rake/tasklib'
require 'tmpdir'
require 'uri'

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

      ##
      # Runs the system command +cmd+ using +Rake.sh+, but filters sensitive
      # data (userinfo part of URIs) in the output message.
      def sh(*cmd, &block)
        Rake.rake_output_message(filter_sensitive_data(cmd.join(' '))) if verbose
        verbose false do
          Rake.sh(*cmd, &block)
        end
      end

      private

      def parse_name_email(str)
        if matched = str.match(/^([^<]*)(?:<([^>]*)>)?$/)
          matched[1..2].map do |val|
            val.strip.empty? ? nil : val.strip if val
          end
        end
      end

      def filter_sensitive_data(str)
        URI.extract(str).each_with_object(str.dup) do |uri, s|
          filtered = URI.parse(uri).tap { |u| u.userinfo &&= '***:***' }.to_s
          s.gsub!(uri, filtered)
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
    #   It takes precedence over the +default_value+. It's evaluated in an
    #   instance context.
    def self.callable_attr(attr_name, default_value = nil, &default_block)
      var_name = "@#{attr_name}".sub('?', '').to_sym

      define_method attr_name do
        value = instance_variable_get(var_name)

        if value.nil? && default_block
          do_in_working_dir { instance_eval &default_block }
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
    # @return [String, Proc] name of the remote branch. Defaults to +gh-page+,
    #   or +master+ if the _remote_url_ matches `#{gh_user}.github.io.git`.
    #
    callable_attr :deploy_branch do
      gh_user = ENV['TRAVIS_REPO_SLUG'].to_s.split('/').first
      remote_url.match(/[:\/]#{gh_user}\.github\.io\.git$/) ? 'master' : 'gh-pages'
    end

    ##
    # @!attribute build_script
    # Defines a function that executes Jekyll to build the site.
    # Defaults to:
    #   puts "\nRunning Jekyll..."
    #   Rake.sh "bundle exec jekyll build --destination #{dest_dir}"
    #
    # @return [Proc] a Proc that accepts one argument; the destination
    #   directory to generate the site into.
    #
    callable_attr :build_script, ->(dest_dir) {
      puts "\nRunning Jekyll..."
      Rake.sh "bundle exec jekyll build --destination #{dest_dir}"
    }

    # For backward compatibility, remove in 2.x.
    alias_method :jekyll_build, :build_script
    alias_method :jekyll_build=, :build_script=

    ##
    # @!attribute override_committer?
    # @return [Boolean, Proc] +true+ to always use {#committer}, +false+ to use
    #   the default committer (configured in git) when available.
    callable_attr :override_committer?, false

    ##
    # @!attribute remote_url
    # Defines URL of the remote git repository to pull and push the built site
    # into. The default is to use URL of the +origin+ remote and:
    #
    # a. if {#ssh_key_file} is readable, then convert URL to SSH address with
    #    user +git+;
    # b. or if environment variable +GT_TOKEN+ is set, then replace +git:+
    #    schema with +https:+ and add +GH_TOKEN+ as an userinfo.
    # c. else use remote URL as is.
    #
    # @return [String, Proc] URL of the target git repository.
    #
    callable_attr :remote_url do
      url = `git config remote.origin.url`.strip.gsub(/^git:/, 'https:')
      next url.gsub(%r{^https://([^/]+)/(.*)$}, 'git@\1:\2') if ssh_key_file?
      next url.gsub(%r{^https://}, "https://#{ENV['GH_TOKEN']}@") if ENV.key? 'GH_TOKEN'
      next url
    end

    ##
    # @!attribute [w] skip_deploy
    # Whether to skip the commit and push phase.
    # Default is to return +true+ when env variable +TRAVIS_PULL_REQUEST+
    # is an integer value greater than 0, +SKIP_DEPLOY+ represents truthy
    # (i.e. contains yes, y, true, or 1), or +SOURCE_BRANCH+ is set and does
    # not match +TRAVIS_BRANCH+.
    #
    # @return [Boolean, Proc] skip deploy?
    #
    callable_attr :skip_deploy? do
      ENV['TRAVIS_PULL_REQUEST'].to_i > 0 ||
        %w[yes y true 1].include?((ENV['SKIP_DEPLOY'] || ENV['SKIP_COMMIT']).to_s.downcase) ||
        (ENV['SOURCE_BRANCH'] && ENV['SOURCE_BRANCH'] != ENV['TRAVIS_BRANCH'])
    end

    # For backward compatibility, remove in 2.x.
    alias_method :skip_commit?, :skip_deploy?
    alias_method :skip_commit=, :skip_deploy=

    ##
    # @!attribute ssh_key_file
    # Defines path of the private SSH key to be used for communication with
    # {#remote_url}. This is optional; when the file doesn't exist, then it's
    # ignored.
    #
    # @note NEVER STORE YOUR PRIVATE SSH KEY IN THE REPOSITORY UNENCRYPTED!
    #
    # @return [String, Proc] path of the private SSH key (default: +.deploy_key+).
    #
    callable_attr :ssh_key_file, '.deploy_key'


    ##
    # @param name [#to_sym] name of the task to define.
    # @yield The block to configure this task.
    def initialize(name = :deploy)
      @name = name
      @description = 'Generate the site and push changes to remote repository'
      @working_dir = Dir.pwd

      yield self if block_given?

      if ssh_key_file?
        ENV['SSH_PRIVATE_KEY'] = "#{@working_dir}/#{ssh_key_file}"
        ENV['GIT_SSH'] = "#{BIN_DIR}/git-ssh-wrapper"
      end

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

          build_script.call(temp_dir)

          Dir.chdir temp_dir do
            unless any_changes?
              puts 'Nothing to commit and deploy.'; next
            end

            if skip_deploy?
              puts 'Skipping deploy.'; next
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

    def ssh_key_file?
      File.readable?(ssh_key_file)
    end
  end
end
