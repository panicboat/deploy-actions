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
  def self.configure
    @container ||= build_container
  end

  def self.resolve(name)
    configure[name]
  end

  private

  def self.build_container
    container = {}

    # Infrastructure clients
    container[:config_client] = Composition.config_client
    container[:directory_scanner] = Composition.directory_scanner

    # Use cases
    container[:resolve_environments] = UseCases::Shared::ResolveEnvironments.new(directory_scanner: container[:directory_scanner])
    container[:enumerate_targets] = UseCases::Shared::EnumerateTargets.new(directory_scanner: container[:directory_scanner])

    container[:validate_config] = UseCases::ConfigManagement::ValidateConfig.new(
      config_client: container[:config_client]
    )

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new

    # Controller
    presenter = Composition.github_actions? ? container[:github_actions_presenter] : container[:console_presenter]
    container[:config_manager_controller] = Interfaces::Controllers::ConfigManagerController.new(
      validate_config_use_case: container[:validate_config],
      resolve_environments_use_case: container[:resolve_environments],
      enumerate_targets_use_case: container[:enumerate_targets],
      config_client: container[:config_client],
      presenter: presenter
    )

    container
  end
end
