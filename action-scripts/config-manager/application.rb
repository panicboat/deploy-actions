# Application setup for config manager
# Configures dependencies and provides access to controllers

require 'bundler/setup'

# Load shared components (adjust path for execution from shared directory)
require_relative '../shared/shared_loader'

# Load feature-specific components
[
  'use_cases/**/*.rb',
  'controllers/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("../config-manager/#{pattern}", __dir__)].sort.each { |file| require file }
end

# Dependency injection container for config manager
class ConfigManagerContainer
  def self.resolve(name)
    @entries ||= {}
    @entries.fetch(name) { @entries[name] = build(name) }
  end

  private

  def self.build(name)
    case name
    when :config_client then Composition.config_client
    when :directory_scanner then Composition.directory_scanner
    when :resolve_environments then UseCases::Shared::ResolveEnvironments.new(directory_scanner: resolve(:directory_scanner))
    when :enumerate_targets then UseCases::Shared::EnumerateTargets.new(directory_scanner: resolve(:directory_scanner))
    when :list_candidates
      UseCases::Shared::ListCandidates.new(
        config_client: resolve(:config_client),
        resolve_environments: resolve(:resolve_environments),
        enumerate_targets: resolve(:enumerate_targets)
      )
    when :validate_config then UseCases::ConfigManagement::ValidateConfig.new(config_client: resolve(:config_client))
    when :test_service then UseCases::ConfigManagement::TestService.new(list_candidates: resolve(:list_candidates))
    when :presenter then Composition.presenter
    when :config_manager_controller
      Interfaces::Controllers::ConfigManagerController.new(
        presenter: resolve(:presenter),
        validate_config: resolve(:validate_config),
        # A builder instead of an instance keeps `validate` runnable outside a git checkout.
        test_service: -> { resolve(:test_service) }
      )
    else
      raise KeyError, "Unknown dependency: #{name}"
    end
  end
end
