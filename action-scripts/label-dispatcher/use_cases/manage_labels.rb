# Use case for managing PR labels based on detected changes
# Handles adding and removing deployment labels on PRs

module UseCases
  module LabelManagement
    class ManageLabels
      attr_reader :github_client

      def initialize(github_client:)
        @github_client = github_client
      end

      # Execute label management for a PR
      def execute(pr_number:, required_labels:)
        # Initial cleanup: Remove all existing deploy labels
        current_deploy_labels = @github_client.get_deploy_labels(pr_number)
        current_deploy_labels.each do |label|
          @github_client.remove_label_from_pr(pr_number, label)
        end

        # Get updated labels (should be empty after cleanup)
        current_deploy_labels = @github_client.get_deploy_labels(pr_number)

        labels_to_add = required_labels - current_deploy_labels
        labels_to_remove = current_deploy_labels - required_labels

        # Ensure all required labels exist in the repository
        required_labels.each do |label|
          @github_client.ensure_label_exists(label)
        end

        # Remove outdated labels
        labels_to_remove.each do |label|
          @github_client.remove_label_from_pr(pr_number, label)
        end

        # Add new labels
        labels_to_add.each do |label|
          @github_client.add_label_to_pr(pr_number, label)
        end

        Entities::Result.success(
          labels_added: labels_to_add,
          labels_removed: labels_to_remove,
          final_labels: required_labels,
          current_labels: current_deploy_labels
        )
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end
    end
  end
end
