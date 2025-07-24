
module UseCases
  class GenerateGotkSync
    def initialize(file_system_repository)
      @file_system = file_system_repository
    end

    def call(environment, repository_url, resource_name = 'flux-system')
      git_repo = Entities::FluxResource.git_repository(
        name: resource_name,
        namespace: 'flux-system',
        url: repository_url
      )

      kustomization = Entities::FluxResource.kustomization(
        name: resource_name,
        namespace: 'flux-system',
        path: environment.cluster_path,
        source_ref: {
          'kind' => 'GitRepository',
          'name' => resource_name
        },
        interval: '10m0s'
      )

      # Fix: Remove the extra YAML separator by removing the leading "---" from the second document
      kustomization_yaml = kustomization.to_yaml.sub(/\A---\n/, '')
      content = git_repo.to_yaml.chomp + "\n---\n" + kustomization_yaml
      file_path = "#{environment.flux_system_path}/gotk-sync.yaml"

      @file_system.write_file(file_path, content)
      puts "📝 Generated gotk-sync for #{environment.name}"
    end

    private

    attr_reader :file_system
  end
end
