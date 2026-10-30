module UseCases
  module LabelResolver
    class GenerateMatrix
      def initialize(config_client:, resolve_environments:, enumerate_targets:)
        @config_client = config_client
        @resolve_environments = resolve_environments
        @enumerate_targets = enumerate_targets
      end

      def execute(deploy_labels:, target_environments:)
        config = @config_client.load_workflow_config
        environments = @resolve_environments.execute(config: config, requested: target_environments)
        return environments if environments.failure?

        labels = deploy_labels.select(&:valid?)
        services = labels.any?(&:deploy_all?) ? nil : labels.map(&:service).uniq
        candidates = @enumerate_targets.execute(config: config, services: services, environments: environments.value)
        return candidates if candidates.failure?

        Entities::Result.success(candidates.value.reject(&:excluded?).map(&:to_deployment_target))
      rescue => error
        Entities::Result.failure("Failed to generate deployment matrix: #{error.message}")
      end
    end
  end
end
