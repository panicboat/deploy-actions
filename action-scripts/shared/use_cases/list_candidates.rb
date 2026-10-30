module UseCases
  module Shared
    class ListCandidates
      def initialize(config_client:, resolve_environments:, enumerate_targets:)
        @config_client = config_client
        @resolve_environments = resolve_environments
        @enumerate_targets = enumerate_targets
      end

      def execute(services:, environments:)
        config = @config_client.load_workflow_config
        resolved = @resolve_environments.execute(config: config, requested: environments)
        return resolved if resolved.failure?

        @enumerate_targets.execute(config: config, services: services, environments: resolved.value)
      end
    end
  end
end
