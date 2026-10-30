module UseCases
  module ConfigManagement
    Validation = Data.define(:config, :summary)

    class ValidateConfig
      def initialize(config_client:)
        @config_client = config_client
      end

      def execute
        config = @config_client.load_workflow_config
        summary = [
          "Configuration validation successful",
          "services: #{config.services.length} configured",
          "stacks: #{config.stacks.length} configured",
          "environments: #{config.environment_names.length} configured"
        ].join("\n")
        Entities::Result.success(Validation.new(config: config, summary: summary))
      rescue StandardError => error
        Entities::Result.failure(error.message)
      end
    end
  end
end
