module Interfaces
  module Presenters
    class GitHubActionsPresenter
      def initialize(output_path:)
        @output_path = output_path
      end

      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:)
        write_outputs(
          'labels-added' => labels_added.to_json,
          'labels-removed' => labels_removed.to_json,
          'services-detected' => deploy_labels.map(&:service).uniq.to_json,
          'has-changes' => deploy_labels.any?.to_s,
        )

        puts TextFormat.label_dispatch(deploy_labels: deploy_labels, labels_added: labels_added, labels_removed: labels_removed, changed_files: changed_files)
      end

      def present_deployment_matrix(deployment_targets:, deploy_labels:, target_environments:, pr_number:)
        write_outputs(
          'targets' => deployment_targets.map(&:to_matrix_item).to_json,
          'has-targets' => deployment_targets.any?.to_s
        )

        puts TextFormat.deployment_matrix(deployment_targets: deployment_targets, deploy_labels: deploy_labels, target_environments: target_environments, pr_number: pr_number)
      end

      def present_service_targets(service:, target_environments:, targets:)
        write_outputs('targets' => targets.map(&:to_matrix_item).to_json, 'has-targets' => targets.any?.to_s)

        puts TextFormat.service_targets(service: service, target_environments: target_environments, targets: targets)
      end

      def present_config_validation_result(valid:, errors: [], summary: nil)
        puts TextFormat.config_validation(valid: valid, errors: errors, summary: summary)
        errors.each { |error| puts "::error::#{error}" } unless valid
      end

      def present_service_test_result(service_name:, candidates:)
        puts TextFormat.service_test_result(service_name: service_name, candidates: candidates)
      end

      def present_error(message)
        puts "::error::#{message}"
      end

      private

      def write_outputs(outputs)
        raise 'GITHUB_OUTPUT is not set' if @output_path.nil?

        File.open(@output_path, 'a') do |file|
          outputs.each { |key, value| file.puts "#{key}=#{value}" }
        end
      end
    end
  end
end
