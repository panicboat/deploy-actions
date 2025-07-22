
module UseCases
  class GenerateAppsKustomization
    def initialize(file_system_repository, manifest_repository)
      @file_system = file_system_repository
      @manifest_repository = manifest_repository
    end

    def call(environment)
      manifests = @manifest_repository.find_manifests_for_environment(environment)

      if manifests.empty?
        puts "⚠️  No YAML files found in #{environment.name} directory"
        resources = []
      else
        resources = build_resources_list(environment, manifests)
        ensure_subdirectories(environment, manifests)
      end

      kustomization = Entities::FluxResource.kustomize_config(resources: resources)
      yaml_content = kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')

      file_path = "#{environment.apps_path}/kustomization.yaml"
      @file_system.write_file(file_path, yaml_content)
      puts "📝 Generated apps kustomization for #{environment.name}"
    end

    private

    attr_reader :file_system, :manifest_repository

    def build_resources_list(environment, manifests)
      manifests.map do |manifest|
        if manifest.in_subdirectory?
          manifest.relative_path
        else
          "#{manifest.service_name}.yaml"
        end
      end
    end

    def ensure_subdirectories(environment, manifests)
      manifests.each do |manifest|
        next unless manifest.in_subdirectory?

        subdirectory_path = "#{environment.apps_path}/#{manifest.directory}"
        @file_system.ensure_directory(subdirectory_path)
      end
    end
  end
end
