# Controller for label resolver functionality

module Interfaces
  module Controllers
    class LabelResolverController
      def initialize(get_labels:, generate_matrix:, presenter:)
        @get_labels = get_labels
        @generate_matrix = generate_matrix
        @presenter = presenter
      end

      def resolve(pr_number:, environments:)
        labels_result = @get_labels.execute(pr_number: pr_number)
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

      private

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end
    end
  end
end
