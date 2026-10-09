module UseCases
  module ConfigManagement
    class ValidateConfig
      def initialize(config_client:)
        @config_client = config_client
      end

      def execute
        config = @config_client.load_workflow_config
        summary = [
          "Configuration validation successful",
          "stacks: #{config.stacks.length} configured",
          "environments: #{config.environment_names.length} configured"
        ].join("\n")
        Entities::Result.success(valid: true, config: config, validation_summary: summary)
      rescue StandardError => error
        Entities::Result.failure(error_message: error.message, validation_errors: [error.message])
      end
    end
  end
end
