# Use case for managing PR labels based on detected changes
# Handles adding and removing deployment labels on PRs

module UseCases
  module LabelManagement
    LabelSync = Data.define(:labels_added, :labels_removed)

    class ManageLabels
      attr_reader :github_client

      def initialize(github_client:, config_client:)
        @github_client = github_client
        @config_client = config_client
      end

      # Execute label management for a PR
      def execute(pr_number:, required_labels:)
        prefix = @config_client.load_workflow_config.label_prefix

        previous_labels = @github_client.get_deploy_labels(pr_number, prefix: prefix)

        # Removing every label before re-adding it fires the labeled event that starts the resolver on each push.
        previous_labels.each do |label|
          @github_client.remove_label_from_pr(pr_number, label)
        end

        required_labels.each do |label|
          @github_client.ensure_label_exists(label)
        end

        required_labels.each do |label|
          @github_client.add_label_to_pr(pr_number, label)
        end

        Entities::Result.success(LabelSync.new(labels_added: required_labels - previous_labels, labels_removed: previous_labels - required_labels))
      rescue => error
        Entities::Result.failure(error.message)
      end
    end
  end
end
