# Shared component loader for workflow automation system
# Loads all shared components in dependency order following Clean Architecture principles

require 'bundler/setup'

# External dependencies
require 'yaml'
require 'json'
require 'octokit'
require 'colorize' unless ENV['GITHUB_ACTIONS']

# Load shared components in Clean Architecture dependency order
[
  'entities/**/*.rb',      # Domain layer (innermost)
  'infrastructure/**/*.rb', # Infrastructure layer
  'interfaces/**/*.rb'     # Interface layer (outermost)
].each do |pattern|
  Dir[File.expand_path("#{pattern}", __dir__)].sort.each { |file| require file }
end

# Loading completion log (development only)
unless ENV['GITHUB_ACTIONS']
  puts "✅ Shared components loaded".colorize(:green)
end
