module UseCases
  module ConfigManagement
    Validation = Data.define(:summary)

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
          "environments: #{config.declared_environment_names.length} configured"
        ].join("\n")
        Entities::Result.success(Validation.new(summary: summary))
      rescue StandardError => error
        Entities::Result.failure(error.message)
      end
    end
  end
end
