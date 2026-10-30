# Controller for label resolver functionality

module Interfaces
  module Controllers
    class LabelResolverController
      def initialize(get_labels:, generate_matrix:, list_candidates:, presenter:)
        @get_labels = get_labels
        @generate_matrix = generate_matrix
        @list_candidates = list_candidates
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
        return failure(Entities::Result.failure("Invalid service name: #{service.inspect} (use all or a name matching [a-zA-Z0-9_-]+)")) unless service.match?(Entities::DeployLabel::SERVICE_PATTERN)

        candidates_result = list_candidates(services: service == 'all' ? nil : [service], environments: environments)
        return failure(candidates_result) if candidates_result.failure?

        @presenter.present_service_targets(service: service, target_environments: environments, candidates: candidates_result.value)
        candidates_result
      end

      private

      def list_candidates(services:, environments:)
        @list_candidates.execute(services: services, environments: environments)
      rescue => error
        Entities::Result.failure("Failed to resolve service targets: #{error.message}")
      end

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end
    end
  end
end
