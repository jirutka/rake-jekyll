require 'bundler/gem_tasks'

begin
  require 'yard'
  # options are defined in .yardopts
  YARD::Rake::YardocTask.new(:yard)
rescue LoadError => e
  warn "#{e.path} is not available"
end
