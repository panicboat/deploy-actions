module UseCases
  module LabelResolver
    class DetermineTargetEnvironment
      def initialize(config_client:, file_client:)
        @config_client = config_client
        @file_client = file_client
      end

      def execute(target_environments:)
        config = @config_client.load_workflow_config
        available = @file_client.environment_names(config: config)
        environments = target_environments.nil? || target_environments.empty? ? available : target_environments.uniq
        unknown = environments - available
        return Entities::Result.failure(error_message: "Target environments not found in configuration: #{unknown.join(', ')}") unless unknown.empty?

        Entities::Result.success(target_environments: environments)
      rescue => error
        Entities::Result.failure(error_message: "Failed to determine target environments: #{error.message}")
      end
    end
  end
end
