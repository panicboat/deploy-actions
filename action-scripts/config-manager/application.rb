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
    when :validate_config then UseCases::ConfigManagement::ValidateConfig.new(config_client: resolve(:config_client))
    when :test_service
      UseCases::ConfigManagement::TestService.new(
        config_client: resolve(:config_client),
        resolve_environments: resolve(:resolve_environments),
        enumerate_targets: resolve(:enumerate_targets)
      )
    when :presenter then build_presenter
    when :config_manager_controller
      Interfaces::Controllers::ConfigManagerController.new(
        presenter: resolve(:presenter),
        validate_config: resolve(:validate_config),
        test_service: resolve(:test_service)
      )
    else
      raise KeyError, "Unknown dependency: #{name}"
    end
  end

  def self.build_presenter
    return Interfaces::Presenters::ConsolePresenter.new unless Composition.github_actions?

    output_path = Composition.github_output_path
    # Checked before the command runs so every CLI rejects a missing GITHUB_OUTPUT before printing any result.
    raise 'GITHUB_OUTPUT is not set' if output_path.nil?

    Interfaces::Presenters::GitHubActionsPresenter.new(output_path: output_path)
  end
end
