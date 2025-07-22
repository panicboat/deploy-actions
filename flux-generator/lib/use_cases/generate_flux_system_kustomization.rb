
module UseCases
  class GenerateFluxSystemKustomization
    def initialize(file_system_repository)
      @file_system = file_system_repository
    end

    def call(environment)
      kustomization = Entities::FluxResource.kustomize_config(
        resources: ['gotk-sync.yaml']
      )

      # Remove empty metadata from kustomize config
      yaml_content = kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')

      file_path = "#{environment.flux_system_path}/kustomization.yaml"
      @file_system.write_file(file_path, yaml_content)
      puts "📝 Generated flux-system kustomization for #{environment.name}"
    end

    private

    attr_reader :file_system
  end
end
