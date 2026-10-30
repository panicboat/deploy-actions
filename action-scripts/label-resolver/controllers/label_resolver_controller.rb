# Controller for label resolver functionality

module Interfaces
  module Controllers
    class LabelResolverController
      def initialize(get_labels:, generate_matrix:, list_service_targets:, presenter:)
        @get_labels = get_labels
        @generate_matrix = generate_matrix
        @list_service_targets = list_service_targets
        @presenter = presenter
      end

      def resolve(pr_number:, environments:)
        labels_result = @get_labels.call.execute(pr_number: pr_number)
        return failure(labels_result) if labels_result.failure?

        matrix_result = @generate_matrix.execute(deploy_labels: labels_result.value, target_environments: environments)
        return failure(matrix_result) if matrix_result.failure?

        @presenter.present_deployment_matrix(
          deployment_targets: matrix_result.value,
          deploy_labels: labels_result.value,
          target_environments: environments,
          pr_number: pr_number
        )
        matrix_result
      end

      def targets(service:, environments:)
        targets_result = @list_service_targets.execute(service: service, environments: environments)
        return failure(targets_result) if targets_result.failure?

        @presenter.present_service_targets(service: service, target_environments: environments, targets: targets_result.value)
        targets_result
      end

      private

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end
    end
  end
end
