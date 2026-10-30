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

    # GitHub client (only in GitHub Actions or with credentials)
    container[:github_client] = begin
      Composition.github_client
    rescue RuntimeError
      raise if Composition.github_actions?
      # SILENT: Local runs without credentials skip the GitHub-backed use cases.
      nil
    end

    # Use cases
    container[:resolve_environments] = UseCases::Shared::ResolveEnvironments.new(directory_scanner: container[:directory_scanner])
    container[:enumerate_targets] = UseCases::Shared::EnumerateTargets.new(directory_scanner: container[:directory_scanner])

    container[:determine_target_environment] = UseCases::LabelResolver::DetermineTargetEnvironment.new(
      config_client: container[:config_client],
      resolve_environments: container[:resolve_environments]
    )

    if container[:github_client]
      container[:get_labels] = UseCases::LabelResolver::GetLabels.new(
        github_client: container[:github_client],
        config_client: container[:config_client]
      )
    end

    container[:validate_deployment_safety] = UseCases::LabelResolver::ValidateDeploymentSafety.new(
      config_client: container[:config_client]
    )

    container[:generate_matrix] = UseCases::LabelResolver::GenerateMatrix.new(
      config_client: container[:config_client],
      resolve_environments: container[:resolve_environments],
      enumerate_targets: container[:enumerate_targets]
    )

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new(output_path: Composition.github_output_path)

    # Controller
    presenter = Composition.github_actions? ? container[:github_actions_presenter] : container[:console_presenter]
    container[:label_resolver_controller] = Interfaces::Controllers::LabelResolverController.new(
      determine_target_environment_use_case: container[:determine_target_environment],
      get_labels_use_case: container[:get_labels],
      validate_deployment_safety_use_case: container[:validate_deployment_safety],
      generate_matrix_use_case: container[:generate_matrix],
      presenter: presenter
    )

    container
  end
end
