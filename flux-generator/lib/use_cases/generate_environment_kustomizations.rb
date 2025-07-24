module UseCases
  class GenerateEnvironmentKustomizations
    def initialize(file_system_repository, manifest_repository)
      @file_system = file_system_repository
      @manifest_repository = manifest_repository
    end

    def call(environment)
      generate_root_kustomization(environment)
      generate_cluster_kustomization(environment)
      generate_services_kustomizations(environment)
    end

    private

    attr_reader :file_system, :manifest_repository

    def generate_root_kustomization(environment)
      # Find all subdirectories that should be included
      manifests = @manifest_repository.find_manifests_for_environment(environment)
      subdirectories = manifests.map(&:directory).uniq.reject { |dir| dir == '.' }

      if subdirectories.empty?
        # No subdirectories, create empty kustomization
        content = generate_empty_kustomization_content
      else
        # Include all subdirectories
        resources = subdirectories.map { |dir| "#{dir}/" }
        content = generate_kustomization_content(resources)
      end

      file_path = "#{environment.name}/kustomization.yaml"
      @file_system.write_file(file_path, content)
      puts "📝 Generated environment kustomization: #{file_path}"
    end

    def generate_cluster_kustomization(environment)
      # The cluster kustomization should include flux-system and apps directories
      resources = ["flux-system/", "apps/"]
      content = generate_kustomization_content(resources)

      file_path = "#{environment.cluster_path}/kustomization.yaml"
      @file_system.write_file(file_path, content)
      puts "📝 Generated cluster kustomization: #{file_path}"
    end

    def generate_services_kustomizations(environment)
      manifests = @manifest_repository.find_manifests_for_environment(environment)

      # Group manifests by directory
      manifests_by_directory = manifests.group_by(&:directory)

      manifests_by_directory.each do |directory, dir_manifests|
        next if directory == '.' # Skip root level manifests

        resources = dir_manifests.map { |manifest| "#{manifest.service_name}.yaml" }
        content = generate_kustomization_content(resources)

        file_path = "#{environment.name}/#{directory}/kustomization.yaml"
        @file_system.write_file(file_path, content)
        puts "📝 Generated service kustomization: #{file_path}"
      end
    end

    def generate_kustomization_content(resources)
      kustomization = Entities::FluxResource.kustomize_config(resources: resources)
      kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')
    end

    def generate_empty_kustomization_content
      kustomization = Entities::FluxResource.kustomize_config(resources: [])
      kustomization.to_yaml.gsub(/^metadata:\s*\{\}\n/, '')
    end
  end
end
