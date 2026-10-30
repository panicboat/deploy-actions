module UseCases
  module ConfigManagement
    class TestService
      def initialize(config_client:, resolve_environments:, enumerate_targets:)
        @config_client = config_client
        @resolve_environments = resolve_environments
        @enumerate_targets = enumerate_targets
      end

      def execute(service_name:, environment:)
        config = @config_client.load_workflow_config
        environments = @resolve_environments.execute(config: config, requested: environment && [environment])
        return environments if environments.failure?

        @enumerate_targets.execute(config: config, services: [service_name], environments: environments.value)
      rescue => error
        Entities::Result.failure("Failed to test service configuration: #{error.message}")
      end
    end
  end
end
