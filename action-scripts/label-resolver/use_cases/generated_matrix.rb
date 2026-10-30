module UseCases
  module LabelResolver
    class GenerateMatrix
      def initialize(list_candidates:)
        @list_candidates = list_candidates
      end

      def execute(deploy_labels:, target_environments:)
        services = deploy_labels.select(&:valid?).map(&:service).uniq
        candidates = @list_candidates.execute(services: services, environments: target_environments)
        return candidates if candidates.failure?

        Entities::Result.success(candidates.value.reject(&:excluded?).map(&:to_deployment_target))
      rescue => error
        Entities::Result.failure("Failed to generate deployment matrix: #{error.message}")
      end
    end
  end
end
