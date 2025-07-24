module Controllers
  class FluxGeneratorController
    def initialize(generate_flux_manifests_use_case, setup_controller)
      @generate_flux_manifests = generate_flux_manifests_use_case
      @setup_controller = setup_controller
    end

    def generate_all(environments, repository_url, resource_name = 'flux-system')
      repository_url ||= detect_repository_url

      unless repository_url
        raise ArgumentError, "Repository URL is required but not provided or detected"
      end

      puts "📋 Configured environments: #{environments.join(',')}"
      puts "🔗 Repository URL: #{repository_url}"
      puts "📛 Resource name: #{resource_name}"

      setup_complete_structure(environments)
      @generate_flux_manifests.call(environments, repository_url, resource_name)
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
  end
end
