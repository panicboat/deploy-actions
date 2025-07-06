# Use case for validating deployment safety before execution

module UseCases
  module DeployTrigger
    class ValidateDeploymentSafety
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute safety validation checks
      def execute(deploy_labels:, merged_pr_number: nil, branch_name:)
        config = @config_client.load_workflow_config
        safety_config = config.raw_config['safety_checks'] || {}

        validation_results = []

        # Check 1: Merged PR requirement
        if safety_config['require_merged_pr']
          pr_check = validate_merged_pr_requirement(merged_pr_number, safety_config)
          validation_results << pr_check
        end

        # Check 2: Deploy labels presence
        if deploy_labels.empty?
          validation_results << {
            check: 'labels_presence',
            passed: true,
            message: 'No deployment labels provided'
          }
        else
          validation_results << {
            check: 'labels_presence',
            passed: true,
            message: "#{deploy_labels.length} deployment labels found"
          }
        end

        # Check 3: Branch pattern validation
        branch_check = validate_branch_pattern(branch_name, config)
        validation_results << branch_check

        # Determine overall safety status
        failed_checks = validation_results.reject { |check| check[:passed] }

        if failed_checks.any?
          fail_on_missing = safety_config['fail_on_missing_pr']

          if fail_on_missing
            return Entities::Result.failure(
              error_message: build_safety_failure_message(failed_checks, branch_name)
            )
          else
            # Warning mode - log but don't fail
            return Entities::Result.success(
              safety_status: 'warning',
              validation_results: validation_results,
              failed_checks: failed_checks,
              deploy_allowed: true
            )
          end
        end

        Entities::Result.success(
          safety_status: 'passed',
          validation_results: validation_results,
          deploy_allowed: true,
          branch_name: branch_name
        )
      rescue => error
        Entities::Result.failure(error_message: "Safety validation failed: #{error.message}")
      end

      private

      # Validate merged PR requirement
      def validate_merged_pr_requirement(merged_pr_number, safety_config)
        if merged_pr_number.nil?
          {
            check: 'merged_pr_requirement',
            passed: false,
            message: 'No merged PR found - deployment may be from direct push'
          }
        else
          {
            check: 'merged_pr_requirement',
            passed: true,
            message: "Merged PR ##{merged_pr_number} found"
          }
        end
      end

      # Validate branch follows expected patterns
      def validate_branch_pattern(branch_name, config)
        branch_patterns = config.raw_config['branch_patterns'] || {}

        if branch_patterns.key?(branch_name)
          {
            check: 'branch_pattern',
            passed: true,
            message: "Branch '#{branch_name}' is configured for deployment"
          }
        else
          {
            check: 'branch_pattern',
            passed: true,
            message: "Branch '#{branch_name}' uses default (develop) environment"
          }
        end
      end

      # Build comprehensive failure message for safety violations
      def build_safety_failure_message(failed_checks, branch_name)
        message = "🚨 DEPLOYMENT STOPPED - Safety validation failed:\n"
        message += "Branch: #{branch_name}\n\n"
        message += "Failed checks:\n"

        failed_checks.each do |check|
          message += "- #{check[:check]}: #{check[:message]}\n"
        end

        message += "\nThis safety check prevents accidental or unauthorized deployments."

        message
      end
    end
  end
end
