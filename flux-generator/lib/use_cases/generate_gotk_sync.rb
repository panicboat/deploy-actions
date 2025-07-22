
module UseCases
  class GenerateGotkSync
    def initialize(file_system_repository)
      @file_system = file_system_repository
    end

    def call(environment, repository_url)
      git_repo = Entities::FluxResource.git_repository(
        name: 'flux-system',
        namespace: 'flux-system',
        url: repository_url
      )

      kustomization = Entities::FluxResource.kustomization(
        name: 'flux-system',
        namespace: 'flux-system',
        path: environment.cluster_path,
        source_ref: {
          'kind' => 'GitRepository',
          'name' => 'flux-system'
        },
        interval: '10m0s'
      )

      content = [git_repo.to_yaml, kustomization.to_yaml].join("---\n")
      file_path = "#{environment.flux_system_path}/gotk-sync.yaml"

      @file_system.write_file(file_path, content)
      puts "📝 Generated gotk-sync for #{environment.name}"
    end

    private

    attr_reader :file_system
  end
end
