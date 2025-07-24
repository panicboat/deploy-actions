module UseCases
  class GenerateFluxManifests
    def initialize(generate_gotk_sync, generate_flux_system_kustomization,
                   generate_apps_kustomization, generate_app_resources,
                   generate_environment_kustomizations)
      @generate_gotk_sync = generate_gotk_sync
      @generate_flux_system_kustomization = generate_flux_system_kustomization
      @generate_apps_kustomization = generate_apps_kustomization
      @generate_app_resources = generate_app_resources
      @generate_environment_kustomizations = generate_environment_kustomizations
    end

    def call(environments, repository_url, resource_name = 'flux-system')
      environments.each do |environment_name|
        environment = Entities::Environment.from_name(environment_name)

        unless environment.valid?
          puts "❌ Invalid environment: #{environment_name}"
          next
        end

        puts "🚀 Generating FluxCD manifests for #{environment.name}..."

        @generate_gotk_sync.call(environment, repository_url, resource_name)
        @generate_flux_system_kustomization.call(environment)
        @generate_apps_kustomization.call(environment)
        @generate_app_resources.call(environment)
        @generate_environment_kustomizations.call(environment)

        puts "✅ Generated FluxCD manifests for #{environment.name}"
      end

      puts "🎉 FluxCD manifests generation completed!"
    end

    private

    attr_reader :generate_gotk_sync, :generate_flux_system_kustomization,
                :generate_apps_kustomization, :generate_app_resources,
                :generate_environment_kustomizations
  end
end
