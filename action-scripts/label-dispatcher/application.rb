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
  def self.resolve(name)
    @entries ||= {}
    @entries.fetch(name) { @entries[name] = build(name) }
  end

  private

  def self.build(name)
    case name
    when :config_client then Composition.config_client
    when :git_client then Composition.git_client
    when :github_client then Composition.github_client
    when :detect_changed_services
      UseCases::LabelManagement::DetectChangedServices.new(config_client: resolve(:config_client), git_client: resolve(:git_client))
    when :manage_labels
      UseCases::LabelManagement::ManageLabels.new(github_client: resolve(:github_client), config_client: resolve(:config_client))
    when :dispatch_labels
      UseCases::LabelManagement::DispatchLabels.new(
        github_client: resolve(:github_client),
        detect_changed_services: resolve(:detect_changed_services),
        manage_labels: resolve(:manage_labels)
      )
    when :presenter then build_presenter
    when :label_dispatcher_controller
      Interfaces::Controllers::LabelDispatcherController.new(
        presenter: resolve(:presenter),
        # A builder instead of an instance keeps `test` runnable without GitHub credentials.
        dispatch_labels: -> { resolve(:dispatch_labels) },
        detect_changed_services: resolve(:detect_changed_services)
      )
    else
      raise KeyError, "Unknown dependency: #{name}"
    end
  end

  def self.build_presenter
    return Interfaces::Presenters::ConsolePresenter.new unless Composition.github_actions?

    output_path = Composition.github_output_path
    # Checked before the command runs so dispatch cannot change labels and then fail to write outputs.
    raise 'GITHUB_OUTPUT is not set' if output_path.nil?

    Interfaces::Presenters::GitHubActionsPresenter.new(output_path: output_path)
  end
end
