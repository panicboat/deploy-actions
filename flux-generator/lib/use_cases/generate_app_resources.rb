
module UseCases
  class GenerateAppResources
    def initialize(file_system_repository, manifest_repository)
      @file_system = file_system_repository
      @manifest_repository = manifest_repository
    end

    def call(environment, resource_name, target_namespace = nil)
      raise ArgumentError, "Resource name is required" if resource_name.nil? || resource_name.empty?
      manifests = @manifest_repository.find_manifests_for_environment(environment)

      manifests.each do |manifest|
        generate_resource_for_manifest(environment, manifest, resource_name, target_namespace)
      end
    end

    private

    attr_reader :file_system, :manifest_repository

    def generate_resource_for_manifest(environment, manifest, resource_name, target_namespace)
      if manifest.in_subdirectory?
        generate_subdirectory_resource(environment, manifest, resource_name, target_namespace)
      else
        generate_root_resource(environment, manifest, resource_name, target_namespace)
      end
    end

    def generate_subdirectory_resource(environment, manifest, resource_name, target_namespace)
      kustomization = Entities::FluxResource.kustomization(
        name: manifest.resource_name,
        namespace: 'flux-system',
        path: "#{environment.path}/#{manifest.directory}",
        source_ref: {
          'kind' => 'GitRepository',
          'name' => resource_name
        },
        interval: '5m0s',
        target_namespace: target_namespace,
        post_build: {
          'substitute' => {
            'service_name' => manifest.service_name
          }
        }
      )

      file_path = "#{environment.apps_path}/#{manifest.relative_path}"
      @file_system.write_file(file_path, kustomization.to_yaml)
      puts "📝 Generated app resource: #{file_path}"
    end

    def generate_root_resource(environment, manifest, resource_name, target_namespace)
      kustomization = Entities::FluxResource.kustomization(
        name: manifest.service_name,
        namespace: 'flux-system',
        path: environment.path,
        source_ref: {
          'kind' => 'GitRepository',
          'name' => resource_name
        },
        interval: '5m0s',
        target_namespace: target_namespace,
        post_build: {
          'substitute' => {
            'service_name' => manifest.service_name
          }
        }
      )

      file_path = "#{environment.apps_path}/#{manifest.service_name}.yaml"
      @file_system.write_file(file_path, kustomization.to_yaml)
      puts "📝 Generated app resource: #{file_path}"
    end
  end
end
