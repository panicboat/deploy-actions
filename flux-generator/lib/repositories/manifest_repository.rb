
module Repositories
  class ManifestRepository
    def initialize(file_system_repository)
      @file_system = file_system_repository
    end

    def find_manifests_for_environment(environment)
      yaml_files = @file_system.find_yaml_files(environment.name)

      # Filter out kustomization.yaml files to avoid self-references
      service_files = yaml_files.reject { |file| File.basename(file) == 'kustomization.yaml' }

      service_files.map do |file_path|
        Entities::ManifestFile.from_path(file_path, environment.name)
      end
    end

    def environment_has_manifests?(environment)
      !find_manifests_for_environment(environment).empty?
    end

    private

    attr_reader :file_system
  end
end
