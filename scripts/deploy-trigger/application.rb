# Application setup for deploy trigger
# Configures dependencies and provides access to controllers

require 'bundler/setup'

# Load shared components (adjust path for execution from shared directory)
require_relative '../shared/shared_loader'

# Load feature-specific components
[
  'use_cases/**/*.rb',
  'controllers/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("../deploy-trigger/#{pattern}", __dir__)].sort.each { |file| require file }
end

# Dependency injection container for deploy trigger
class DeployTriggerContainer
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
    container[:config_client] = Infrastructure::ConfigClient.new

    # GitHub client (only in GitHub Actions or with credentials)
    if ENV['GITHUB_ACTIONS'] || (ENV['GITHUB_TOKEN'] && ENV['GITHUB_REPOSITORY'])
      container[:github_client] = Infrastructure::GitHubClient.new(
        token: ENV['GITHUB_TOKEN'] || raise('GITHUB_TOKEN is required'),
        repository: ENV['GITHUB_REPOSITORY'] || raise('GITHUB_REPOSITORY is required')
      )
    end

    # Use cases
    container[:determine_target_environment] = UseCases::DeployTrigger::DetermineTargetEnvironment.new(
      config_client: container[:config_client]
    )

    if container[:github_client]
      container[:get_merged_pr_labels] = UseCases::DeployTrigger::GetMergedPrLabels.new(
        github_client: container[:github_client]
      )
    end

    container[:validate_deployment_safety] = UseCases::DeployTrigger::ValidateDeploymentSafety.new(
      config_client: container[:config_client]
    )

    container[:generate_matrix] = UseCases::DeployTrigger::GenerateMatrix.new(
      config_client: container[:config_client]
    )

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new

    # Controller
    presenter = ENV['GITHUB_ACTIONS'] ? container[:github_actions_presenter] : container[:console_presenter]
    container[:deploy_trigger_controller] = Interfaces::Controllers::DeployTriggerController.new(
      determine_target_environment_use_case: container[:determine_target_environment],
      get_merged_pr_labels_use_case: container[:get_merged_pr_labels],
      validate_deployment_safety_use_case: container[:validate_deployment_safety],
      generate_matrix_use_case: container[:generate_matrix],
      presenter: presenter
    )

    container
  end
end

# Loading completion log (development only)
unless ENV['GITHUB_ACTIONS']
  puts "✅ Deploy Trigger loaded".colorize(:green)
end
