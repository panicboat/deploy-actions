module UseCases
  module LabelResolver
    class DetermineTargetEnvironment
      def initialize(config_client:)
        @config_client = config_client
      end

      def execute(target_environments:)
        config = @config_client.load_workflow_config
        environments = target_environments.nil? || target_environments.empty? ? config.environment_names : target_environments.uniq
        unknown = environments - config.environment_names
        return Entities::Result.failure(error_message: "Target environments not found in configuration: #{unknown.join(', ')}") unless unknown.empty?

        Entities::Result.success(target_environments: environments)
      rescue => error
        Entities::Result.failure(error_message: "Failed to determine target environments: #{error.message}")
      end
    end
  end
end
