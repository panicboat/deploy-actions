# Use case for determining target environment from branch name

module UseCases
  module LabelResolver
    class DetermineTargetEnvironment
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute target environment determination
      def execute(branch_name:)
        config = @config_client.load_workflow_config
        
        target_environment = config.branch_to_environment(branch_name) || 'develop'

        # Validate environment exists in configuration
        unless config.environments.key?(target_environment)
          return Entities::Result.failure(
            error_message: "Target environment '#{target_environment}' not found in configuration"
          )
        end

        Entities::Result.success(
          target_environment: target_environment,
          branch_name: branch_name,
          environment_config: config.environment_config(target_environment)
        )
      rescue => error
        Entities::Result.failure(error_message: "Failed to determine target environment: #{error.message}")
      end
    end
  end
end
