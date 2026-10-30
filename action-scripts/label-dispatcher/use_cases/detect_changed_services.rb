module UseCases
  module LabelManagement
    Detection = Data.define(:deploy_labels, :changed_files)
    class DetectChangedServices
      def initialize(config_client:, git_client:)
        @config_client = config_client
        @git_client = git_client
      end

      def execute(base_ref: nil, head_ref: nil)
        config = @config_client.load_workflow_config
        changed_files = @git_client.changed_files(base_ref: base_ref, head_ref: head_ref)
        labels = Entities::ChangeDetector.new(config).services(changed_files).map { |service| Entities::DeployLabel.from_service(service: service, prefix: config.label_prefix) }
        Entities::Result.success(Detection.new(deploy_labels: labels, changed_files: changed_files))
      rescue => error
        Entities::Result.failure(error.message)
      end
    end
  end
end
