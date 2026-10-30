# Application setup for label dispatcher
# Configures dependencies and provides access to controllers

require 'bundler/setup'

# Load shared components (adjust path for execution from shared directory)
require_relative '../shared/shared_loader'

# Load feature-specific components
[
  'use_cases/**/*.rb',
  'controllers/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("../label-dispatcher/#{pattern}", __dir__)].sort.each { |file| require file }
end

# Dependency injection container for label dispatcher
class LabelDispatcherContainer
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
    container[:git_client] = Composition.git_client
    container[:config_client] = Composition.config_client

    # GitHub client (only in GitHub Actions or with credentials)
    container[:github_client] = begin
      Composition.github_client
    rescue RuntimeError
      raise if Composition.github_actions?
      # SILENT: Local runs without credentials skip the GitHub-backed use cases.
      nil
    end

    # Use cases
    container[:detect_changed_services] = UseCases::LabelManagement::DetectChangedServices.new(
      config_client: container[:config_client],
      git_client: container[:git_client]
    )

    if container[:github_client]
      container[:manage_labels] = UseCases::LabelManagement::ManageLabels.new(
        github_client: container[:github_client],
        config_client: container[:config_client]
      )
    end

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new(output_path: Composition.github_output_path)

    # Controller
    presenter = Composition.github_actions? ? container[:github_actions_presenter] : container[:console_presenter]
    container[:label_dispatcher_controller] = Interfaces::Controllers::LabelDispatcherController.new(
      detect_services_use_case: container[:detect_changed_services],
      manage_labels_use_case: container[:manage_labels],
      presenter: presenter
    )

    container
  end
end
