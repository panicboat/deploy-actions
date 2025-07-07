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
    container[:config_client] = Infrastructure::ConfigClient.new

    # Use cases
    container[:validate_config] = UseCases::ConfigManagement::ValidateConfig.new(
      config_client: container[:config_client]
    )

    # Presenters
    container[:console_presenter] = Interfaces::Presenters::ConsolePresenter.new
    container[:github_actions_presenter] = Interfaces::Presenters::GitHubActionsPresenter.new

    # Controller
    presenter = ENV['GITHUB_ACTIONS'] ? container[:github_actions_presenter] : container[:console_presenter]
    container[:config_manager_controller] = Interfaces::Controllers::ConfigManagerController.new(
      validate_config_use_case: container[:validate_config],
      config_client: container[:config_client],
      presenter: presenter
    )

    container
  end
end

# Loading completion log (development only)
unless ENV['GITHUB_ACTIONS']
  puts "✅ Config Manager loaded".colorize(:green)
end
