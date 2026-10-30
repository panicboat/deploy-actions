# Application setup for label resolver
# Configures dependencies and provides access to controllers

require 'bundler/setup'

# Load shared components (adjust path for execution from shared directory)
require_relative '../shared/shared_loader'

# Load feature-specific components
[
  'use_cases/**/*.rb',
  'controllers/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("../label-resolver/#{pattern}", __dir__)].sort.each { |file| require file }
end

# Dependency injection container for label resolver
class LabelResolverContainer
  def self.resolve(name)
    @entries ||= {}
    @entries.fetch(name) { @entries[name] = build(name) }
  end

  private

  def self.build(name)
    case name
    when :config_client then Composition.config_client
    when :directory_scanner then Composition.directory_scanner
    when :github_client then Composition.github_client
    when :resolve_environments then UseCases::Shared::ResolveEnvironments.new(directory_scanner: resolve(:directory_scanner))
    when :enumerate_targets then UseCases::Shared::EnumerateTargets.new(directory_scanner: resolve(:directory_scanner))
    when :get_labels
      UseCases::LabelResolver::GetLabels.new(github_client: resolve(:github_client), config_client: resolve(:config_client))
    when :generate_matrix
      UseCases::LabelResolver::GenerateMatrix.new(
        config_client: resolve(:config_client),
        resolve_environments: resolve(:resolve_environments),
        enumerate_targets: resolve(:enumerate_targets)
      )
    when :presenter then Composition.presenter
    when :label_resolver_controller
      Interfaces::Controllers::LabelResolverController.new(
        presenter: resolve(:presenter),
        get_labels: resolve(:get_labels),
        generate_matrix: resolve(:generate_matrix)
      )
    else
      raise KeyError, "Unknown dependency: #{name}"
    end
  end
end
