# Use case for managing PR labels based on detected changes
# Handles adding and removing deployment labels on PRs
# Phase 1: Added support for excluded services display

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

      # Update PR comment with deployment information including excluded services
      def update_deployment_comment(pr_number:, deploy_labels:, changed_files:, excluded_services: [], excluded_services_config: {})
        content = build_deployment_comment_content(deploy_labels, changed_files, excluded_services, excluded_services_config)
        tag = 'auto-deployment-info'

        @github_client.update_pr_comment(pr_number, content, tag)

        Entities::Result.success(comment_updated: true)
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end

      private

      # Build the content for deployment information comment
      def build_deployment_comment_content(deploy_labels, changed_files, excluded_services = [], excluded_services_config = {})
        content = "## 🚀 Auto-Deployment Information\n\n"

        if deploy_labels.any?
          content += "### ✅ Automated Services (#{deploy_labels.length})\n"
          deploy_labels.each do |label|
            content += "- **#{label.service}**\n"
          end
          content += "\n"

          content += "### 🏷️ Deployment Labels Applied\n"
          deploy_labels.each do |label|
            content += "- `#{label.to_s}`\n"
          end
          content += "\n"
        end

        if excluded_services.any?
          content += "### ⚠️ Manual Deployment Required (#{excluded_services.length})\n"
          excluded_services.each do |service|
            service_config = excluded_services_config[service] || {}
            reason = service_config[:reason] || 'Manual deployment required'
            type = service_config[:type] || 'unspecified'

            type_emoji = case type
                        when 'permanent' then '🔒'
                        when 'temporary' then '⏱️'
                        when 'conditional' then '🔀'
                        else '📋'
                        end

            content += "- #{type_emoji} **#{service}** (#{type}): #{reason}\n"
          end
          content += "\n"
          content += "### 📝 Manual Deployment Instructions\n"
          content += "For excluded services, please follow manual deployment procedures:\n"
          excluded_services.each do |service|
            content += "- **#{service}**: Check service-specific documentation or contact service owner\n"
          end
          content += "\n"
        end

        if deploy_labels.empty? && excluded_services.empty?
          content += "No deployment targets detected for this PR.\n\n"
        end

        content += "### 📋 Changed Files (#{changed_files.length})\n"
        if changed_files.length <= 20
          changed_files.each { |file| content += "- `#{file}`\n" }
        else
          content += "<details>\n<summary>Show all #{changed_files.length} changed files</summary>\n\n"
          changed_files.each { |file| content += "- `#{file}`\n" }
          content += "\n</details>\n"
        end

        content += "\n---\n*This comment is automatically updated when the PR changes.*"
        content
      end
    end
  end
end
