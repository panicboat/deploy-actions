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
    container[:file_client] = Infrastructure::FileSystemClient.new
    container[:config_client] = Infrastructure::ConfigClient.new

    # GitHub client (only in GitHub Actions or with credentials)
    if ENV['GITHUB_ACTIONS'] || (ENV['GITHUB_TOKEN'] && ENV['GITHUB_REPOSITORY'])
      container[:github_client] = Infrastructure::GitHubClient.new(
        token: ENV['GITHUB_TOKEN'] || raise('GITHUB_TOKEN is required'),
        repository: ENV['GITHUB_REPOSITORY'] || raise('GITHUB_REPOSITORY is required')
      )
    end

    # Use cases
    container[:detect_changed_services] = UseCases::LabelManagement::DetectChangedServices.new(
      file_client: container[:file_client],
      config_client: container[:config_client]
    )

    if container[:github_client]
      container[:manage_labels] = UseCases::LabelManagement::ManageLabels.new(
        github_client: container[:github_client]
      )
    end

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new

    # Controller
    presenter = ENV['GITHUB_ACTIONS'] ? container[:github_actions_presenter] : container[:console_presenter]
    container[:label_dispatcher_controller] = Interfaces::Controllers::LabelDispatcherController.new(
      detect_services_use_case: container[:detect_changed_services],
      manage_labels_use_case: container[:manage_labels],
      presenter: presenter
    )

    container
  end
end

# Loading completion log (development only)
unless ENV['GITHUB_ACTIONS']
  puts "✅ Label Dispatcher loaded".colorize(:green)
end
