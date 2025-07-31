# Use case for determining target environment

module UseCases
  module LabelResolver
    class DetermineTargetEnvironment
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute target environments determination
      def execute(target_environments:)
        config = @config_client.load_workflow_config

        # Validate all environments exist in configuration
        validated_environments = []
        environment_configs = {}

        target_environments.each do |env|
          unless config.environments.key?(env)
            return Entities::Result.failure(
              error_message: "Target environment '#{env}' not found in configuration"
            )
          end
          validated_environments << env
          environment_configs[env] = config.environment_config(env)
        end

        Entities::Result.success(
          target_environments: validated_environments,
          environment_configs: environment_configs
        )
      rescue => error
        Entities::Result.failure(error_message: "Failed to determine target environments: #{error.message}")
      end
    end
  end
end
