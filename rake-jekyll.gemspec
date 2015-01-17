# coding: utf-8
require File.expand_path('lib/rake-jekyll/version', __dir__)

Gem::Specification.new do |s|
  s.name          = 'rake-jekyll'
  s.version       = Rake::Jekyll::VERSION
  s.author        = 'Jakub Jirutka'
  s.email         = 'jakub@jirutka.cz'
  s.homepage      = 'https://github.com/jirutka/rake-jekyll'
  s.license       = 'MIT'

  s.summary       = 'Rake tasks for Jekyll.'
  s.description   = 'Tasks for deploying Jekyll site to Git etc.'

  begin
    s.files       = `git ls-files -z -- */* {LICENSE,Rakefile,README}*`.split("\x0")
  rescue
    s.files       = Dir['**/*']
  end

  s.require_paths = ['lib']
  s.has_rdoc      = 'yard'

  s.required_ruby_version = '>= 2.0'

  s.add_runtime_dependency 'rake', '~> 10.0'

  s.add_development_dependency 'bundler', '~> 1.6'
  s.add_development_dependency 'yard', '~> 0.8'
end
