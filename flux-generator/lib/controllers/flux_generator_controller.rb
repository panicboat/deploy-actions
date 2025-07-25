module Controllers
  class FluxGeneratorController
    def initialize(generate_flux_manifests_use_case, setup_controller)
      @generate_flux_manifests = generate_flux_manifests_use_case
      @setup_controller = setup_controller
    end

    def generate_all(environments, repository_url, resource_name = nil, target_namespace = nil)
      repository_url ||= detect_repository_url
      resource_name ||= generate_default_resource_name

      unless repository_url
        raise ArgumentError, "Repository URL is required but not provided or detected"
      end

      if resource_name.nil? || resource_name.empty?
        raise ArgumentError, "Resource name is required"
      end

      puts "📋 Configured environments: #{environments.join(',')}"
      puts "🔗 Repository URL: #{repository_url}"
      puts "📛 Resource name: #{resource_name}"

      setup_complete_structure(environments)
      @generate_flux_manifests.call(environments, repository_url, resource_name, target_namespace)
    end

    private

    attr_reader :generate_flux_manifests, :setup_controller

    def setup_complete_structure(environments)
      @setup_controller.setup_directories(environments)
      @setup_controller.setup_missing_directories
      @setup_controller.setup_missing_kustomizations(environments)
    end

    def detect_repository_url
      github_repository = ENV['GITHUB_REPOSITORY']
      return nil unless github_repository

      "https://github.com/#{github_repository}"
    end

    def generate_default_resource_name
      require 'securerandom'
      "flux-#{SecureRandom.hex(8)}"
    end
  end
end
