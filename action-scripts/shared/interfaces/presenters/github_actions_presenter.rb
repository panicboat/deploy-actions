# GitHub Actions presenter for formatting output for GitHub Actions workflows
# Handles environment variable setting and action outputs

module Interfaces
  module Presenters
    class GitHubActionsPresenter
      # Present label dispatch results for GitHub Actions
      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:, excluded_services: [])
        set_environment_variables(
          'DEPLOY_LABELS' => deploy_labels.map(&:to_s).to_json,
          'LABELS_ADDED' => labels_added.to_json,
          'LABELS_REMOVED' => labels_removed.to_json,
          'HAS_CHANGES' => deploy_labels.any?.to_s,
          'CHANGED_FILES' => changed_files.to_json,
          'SERVICES_DETECTED' => deploy_labels.map(&:service).uniq.to_json,
          'EXCLUDED_SERVICES' => excluded_services.to_json,
          'HAS_EXCLUDED_SERVICES' => excluded_services.any?.to_s
        )

        set_action_outputs(
          'deploy-labels' => deploy_labels.map(&:to_s).to_json,
          'labels-added' => labels_added.to_json,
          'labels-removed' => labels_removed.to_json,
          'services-detected' => deploy_labels.map(&:service).uniq.to_json,
          'has-changes' => deploy_labels.any?.to_s,
          'excluded-services' => excluded_services.to_json,
          'has-excluded-services' => excluded_services.any?.to_s
        )

        puts "🏷️ Label Dispatch Completed"
        puts "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
        puts "Labels Added: #{labels_added.join(', ')}" if labels_added.any?
        puts "Labels Removed: #{labels_removed.join(', ')}" if labels_removed.any?
        puts "Excluded Services: #{excluded_services.join(', ')}" if excluded_services.any?
      end

      # Present deployment matrix for GitHub Actions
      def present_deployment_matrix(
        deployment_targets:,
        deploy_labels:,
        branch_name: nil,
        target_environment: nil,
        merged_pr_number: nil,
        pr_number: nil,
        safety_status: nil
      )
        matrix_items = deployment_targets.map(&:to_matrix_item)

        set_environment_variables(
          'DEPLOYMENT_TARGETS' => matrix_items.to_json,
          'HAS_TARGETS' => deployment_targets.any?.to_s,
          'DEPLOY_LABELS' => deploy_labels.map(&:to_s).to_json,
          'TARGET_ENVIRONMENT' => target_environment,
          'BRANCH_NAME' => branch_name,
          'MERGED_PR_NUMBER' => merged_pr_number || pr_number,
          'SAFETY_STATUS' => safety_status
        )

        set_action_outputs(
          'targets' => matrix_items.to_json,
          'has-targets' => deployment_targets.any?.to_s,
          'target-environment' => target_environment,
          'safety-status' => safety_status
        )

        puts "🚀 Deployment Matrix Generated"
        puts "Targets: #{deployment_targets.length} deployment(s)"
        puts "Target Environment: #{target_environment}" if target_environment
        puts "Branch: #{branch_name}" if branch_name
        puts "PR: ##{merged_pr_number || pr_number}" if merged_pr_number || pr_number

        deployment_targets.each do |target|
          puts "  #{target.service}:#{target.environment}:#{target.stack} -> #{target.working_directory}"
        end
      end

      # Present branch deployment results for GitHub Actions
      def present_branch_deployment_result(deploy_labels:, branch_name:)
        # This method is no longer used with the new architecture
        # But keeping for backward compatibility
        puts "🌿 Branch Deployment Detection"
        puts "Branch: #{branch_name}"
        puts "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
      end

      # Present configuration validation results for GitHub Actions
      def present_config_validation_result(valid:, errors: [], config: nil, summary: nil)
        set_environment_variables(
          'CONFIG_VALID' => valid.to_s,
          'CONFIG_ERRORS' => errors.to_json
        )

        set_action_outputs(
          'config_valid' => valid.to_s
        )

        if valid
          puts "✅ Configuration is valid"
          if summary
            puts "Summary:"
            if summary.is_a?(String)
              puts summary
            else
              summary.each { |key, value| puts "  #{key}: #{value}" }
            end
          end
        else
          puts "❌ Configuration validation failed"
          errors.each { |error| puts "  - #{error}" }
        end
      end

      # Present configuration details
      def present_config_details(config:)
        puts "📋 Workflow Configuration"
        puts "Environments: #{config.environments.keys.join(', ')}"
        puts "Services: #{config.services.keys.join(', ')}"
        puts "Terraform version: #{config.terraform_version}"
        puts "Terragrunt version: #{config.terragrunt_version}"

        puts "\nDirectory Conventions:"
        config.directory_conventions.each { |stack, pattern| puts "  #{stack}: #{pattern}" }
      end

      # Present service test results
      def present_service_test_result(service_name:, environment:, env_config:, service_config:, terragrunt_directory:, kubernetes_directory:)
        puts "🔧 Service Configuration Test"
        puts "Service: #{service_name}"
        puts "Environment: #{environment}"
        puts "Terragrunt Directory: #{terragrunt_directory}"
        puts "Kubernetes Directory: #{kubernetes_directory}"
        puts "IAM Plan Role: #{env_config['iam_role_plan']}"
        puts "IAM Apply Role: #{env_config['iam_role_apply']}"
        puts "AWS Region: #{env_config['aws_region']}"
      end

      # Present diagnostic results
      def present_diagnostic_results(results:)
        puts "🏥 Diagnostic Results"
        results.each do |result|
          status_icon = case result[:status]
                       when 'PASS' then '✅'
                       when 'WARN' then '⚠️'
                       when 'FAIL' then '❌'
                       else '❓'
                       end

          puts "#{status_icon} #{result[:check]}: #{result[:details]}"
        end
      end

      # Present config template
      def present_config_template(template:)
        puts "📋 Configuration Template"
        puts ""
        puts template
      end

      # Present error results for GitHub Actions
      def present_error(result)
        set_environment_variables(
          'ERROR_OCCURRED' => 'true',
          'ERROR_MESSAGE' => result.error_message
        )

        puts "::error::#{result.error_message}"
        exit 1
      end

      # Present service discovery results
      def present_service_discovery_result(discovered_services:, method:)
        puts "🔍 Service Discovery Results"
        puts "Discovery Method: #{method}"
        puts "Discovered Services: #{discovered_services.join(', ')}"
      end

      private

      # Set GitHub Actions environment variables
      def set_environment_variables(variables)
        return unless ENV['GITHUB_ENV']

        File.open(ENV['GITHUB_ENV'], 'a') do |f|
          variables.each { |key, value| f.puts "#{key}=#{value}" }
        end
      end

      # Set GitHub Actions step outputs
      def set_action_outputs(outputs)
        github_output = ENV['GITHUB_OUTPUT']
        if github_output && File.exist?(github_output)
          # Use new GITHUB_OUTPUT format
          outputs.each do |key, value|
            File.open(github_output, 'a') do |file|
              file.puts "#{key}=#{value}"
            end
          end
        else
          # Fallback to legacy format for local testing
          outputs.each do |key, value|
            puts "::set-output name=#{key}::#{value}"
          end
        end
      end
    end
  end
end
