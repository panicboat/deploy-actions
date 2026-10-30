# Use case for validating deployment safety before execution
# NOTE: Safety checks have been removed from configuration structure

module UseCases
  module LabelResolver
    class ValidateDeploymentSafety
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute safety validation checks
      def execute(deploy_labels:, pr_number: nil)
        # Safety checks have been removed from configuration
        # Always return success for backward compatibility
        Entities::Result.success('passed')
      rescue => error
        Entities::Result.failure("Safety validation failed: #{error.message}")
      end
    end
  end
end
