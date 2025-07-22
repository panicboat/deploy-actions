# Application setup for FluxCD manifest generator
# Configures dependencies and provides access to controllers

require 'bundler/setup'
require 'dry-container'
require 'dry-auto_inject'
require 'yaml'
require 'pathname'

# Load all components
[
  'entities/**/*.rb',
  'repositories/**/*.rb', 
  'use_cases/**/*.rb',
  'controllers/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("lib/#{pattern}", __dir__)].sort.each { |file| require file }
end

# Dependency injection container for FluxCD generator
class FluxGeneratorContainer
  def self.configure
    @container ||= build_container
  end

  def self.resolve(name)
    configure[name]
  end

  private

  def self.build_container
    container = {}

    # Infrastructure - Repositories
    container[:file_system_repository] = Repositories::FileSystemRepository.new
    container[:manifest_repository] = Repositories::ManifestRepository.new(
      container[:file_system_repository]
    )

    # Use Cases
    container[:generate_gotk_sync] = UseCases::GenerateGotkSync.new(
      container[:file_system_repository]
    )

    container[:generate_flux_system_kustomization] = UseCases::GenerateFluxSystemKustomization.new(
      container[:file_system_repository]
    )

    container[:generate_apps_kustomization] = UseCases::GenerateAppsKustomization.new(
      container[:file_system_repository],
      container[:manifest_repository]
    )

    container[:generate_app_resources] = UseCases::GenerateAppResources.new(
      container[:file_system_repository],
      container[:manifest_repository]
    )

    container[:generate_environment_kustomizations] = UseCases::GenerateEnvironmentKustomizations.new(
      container[:file_system_repository],
      container[:manifest_repository]
    )

    container[:generate_flux_manifests] = UseCases::GenerateFluxManifests.new(
      container[:generate_gotk_sync],
      container[:generate_flux_system_kustomization],
      container[:generate_apps_kustomization],
      container[:generate_app_resources],
      container[:generate_environment_kustomizations]
    )

    # Controllers
    container[:setup_controller] = Controllers::SetupController.new(
      container[:file_system_repository]
    )

    container[:validation_controller] = Controllers::ValidationController.new(
      container[:file_system_repository],
      container[:manifest_repository]
    )

    container[:flux_generator_controller] = Controllers::FluxGeneratorController.new(
      container[:generate_flux_manifests],
      container[:setup_controller]
    )

    container
  end
end

# Loading completion log (development only)
unless ENV['GITHUB_ACTIONS']
  puts "✅ FluxCD Generator loaded"
end