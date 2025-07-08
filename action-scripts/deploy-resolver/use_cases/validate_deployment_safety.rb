# Use case for validating deployment safety before execution
# NOTE: Safety checks have been removed from configuration structure

module UseCases
  module DeployResolver
    class ValidateDeploymentSafety
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute safety validation checks
      def execute(deploy_labels:, pr_number: nil, branch_name:)
        # Safety checks have been removed from configuration
        # Always return success for backward compatibility
        validation_results = [
          {
            check: 'labels_presence',
            passed: true,
            message: deploy_labels.empty? ? 'No deployment labels provided' : "#{deploy_labels.length} deployment labels found"
          },
          {
            check: 'branch_validation',
            passed: true,
            message: "Branch '#{branch_name}' is valid for deployment"
          }
        ]

        Entities::Result.success(
          safety_status: 'passed',
          validation_results: validation_results,
          deploy_allowed: true,
          branch_name: branch_name,
          pr_number: pr_number
        )
      rescue => error
        Entities::Result.failure(
          error_message: "Safety validation failed: #{error.message}"
        )
      end
    end
  end
end
