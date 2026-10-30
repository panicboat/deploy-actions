module UseCases
  module LabelResolver
    class DetermineTargetEnvironment
      def initialize(config_client:, resolve_environments:)
        @config_client = config_client
        @resolve_environments = resolve_environments
      end

      def execute(target_environments:)
        config = @config_client.load_workflow_config
        @resolve_environments.execute(config: config, requested: target_environments)
      rescue => error
        Entities::Result.failure("Failed to determine target environments: #{error.message}")
      end
    end
  end
end
