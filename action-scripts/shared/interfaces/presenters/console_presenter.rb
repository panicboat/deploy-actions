require 'colorize'

module Interfaces
  module Presenters
    class ConsolePresenter
      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:)
        print_lines(TextFormat.label_dispatch(deploy_labels: deploy_labels, labels_added: labels_added, labels_removed: labels_removed, changed_files: changed_files), heading_color: :blue)
      end

      def present_deployment_matrix(deployment_targets:, deploy_labels:, target_environments:, pr_number:)
        print_lines(TextFormat.deployment_matrix(deployment_targets: deployment_targets, deploy_labels: deploy_labels, target_environments: target_environments, pr_number: pr_number), heading_color: :green)
      end

      def present_service_targets(service:, target_environments:, targets:)
        print_lines(TextFormat.service_targets(service: service, target_environments: target_environments, targets: targets), heading_color: :green)
      end

      def present_config_validation_result(valid:, errors: [], summary: nil)
        print_lines(TextFormat.config_validation(valid: valid, errors: errors, summary: summary), heading_color: valid ? :green : :red)
      end

      def present_service_test_result(service_name:, candidates:)
        print_lines(TextFormat.service_test_result(service_name: service_name, candidates: candidates))
      end

      def present_error(message)
        puts "❌ Error: #{message}".colorize(:red)
      end

      private

      def print_lines(lines, heading_color: nil)
        heading, *rest = lines
        puts heading_color ? heading.colorize(heading_color) : heading
        rest.each { |line| puts line }
      end
    end
  end
end
