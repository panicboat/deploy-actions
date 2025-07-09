# Console presenter for displaying results in terminal output
# Provides formatted output for development and testing

module Interfaces
  module Presenters
    class ConsolePresenter
      # Present label dispatch results
      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:, excluded_services: [])
        puts "🏷️  Label Dispatch Results".colorize(:blue)
        puts "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
        puts "Labels Added: #{labels_added.join(', ')}" if labels_added.any?
        puts "Labels Removed: #{labels_removed.join(', ')}" if labels_removed.any?

        if excluded_services.any?
          puts "Excluded Services: #{excluded_services.join(', ')}".colorize(:yellow)
        end

        puts "Changed Files: #{changed_files.length} files"

        if changed_files.length <= 10
          changed_files.each { |file| puts "  - #{file}" }
        else
          puts "  (showing first 10 files)"
          changed_files.first(10).each { |file| puts "  - #{file}" }
          puts "  ... and #{changed_files.length - 10} more files"
        end
      end

      # Present deployment matrix results
      def present_deployment_matrix(
        deployment_targets:,
        deploy_labels:,
        branch_name: nil,
        target_environment: nil,
        merged_pr_number: nil,
        pr_number: nil,
        safety_status: nil
      )
        puts "🚀 Deployment Matrix".colorize(:green)

        # Show context information
        puts "Target Environment: #{target_environment}" if target_environment
        puts "Branch: #{branch_name}" if branch_name
        puts "PR Number: ##{merged_pr_number || pr_number}" if merged_pr_number || pr_number
        puts "Safety Status: #{safety_status}" if safety_status
        puts ""

        puts "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
        puts "Deployment Targets: #{deployment_targets.length}"

        deployment_targets.each do |target|
          puts "  #{target.service}:#{target.environment}:#{target.stack} -> #{target.working_directory}"
          puts "    IAM Plan Role: #{target.iam_role_plan}" if target.iam_role_plan
          puts "    IAM Apply Role: #{target.iam_role_apply}" if target.iam_role_apply
          puts "    AWS Region: #{target.aws_region}"
          puts ""
        end
      end

      # Present branch deployment results
      def present_branch_deployment_result(deploy_labels:, branch_name:)
        puts "🌿 Branch Deployment Detection".colorize(:blue)
        puts "Branch: #{branch_name}"
        puts "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
      end

      # Present configuration validation results
      def present_config_validation_result(valid:, errors: [], config: nil, summary: nil)
        if valid
          puts "✅ Configuration is valid".colorize(:green)
          if summary
            puts "Summary:"
            if summary.is_a?(String)
              puts summary
            else
              summary.each { |key, value| puts "  #{key}: #{value}" }
            end
          end
        else
          puts "❌ Configuration validation failed".colorize(:red)
          errors.each { |error| puts "  - #{error}" }
        end
      end

      # Present configuration details
      def present_config_details(config:)
        puts "📋 Workflow Configuration".colorize(:blue)
        puts "Environments: #{config.environments.keys.join(', ')}"
        puts "Services: #{config.services.keys.join(', ')}"

        puts "\nDirectory Conventions:"
        config.directory_conventions.each { |stack, pattern| puts "  #{stack}: #{pattern}" }
      end

      # Present service test results
      def present_service_test_result(service_name:, environment:, env_config:, service_config:, terragrunt_directory:, kubernetes_directory:)
        puts "🔧 Service Configuration Test".colorize(:blue)
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
        puts "🏥 Diagnostic Results".colorize(:blue)
        results.each do |result|
          status_color = case result[:status]
                        when 'PASS' then :green
                        when 'WARN' then :yellow
                        when 'FAIL' then :red
                        else :white
                        end

          puts "#{result[:status].ljust(4)} #{result[:check]}: #{result[:details]}".colorize(status_color)
        end
      end

      # Present config template
      def present_config_template(template:)
        puts "📋 Configuration Template".colorize(:blue)
        puts ""
        puts template
      end

      # Present error results
      def present_error(result)
        puts "❌ Error: #{result.error_message}".colorize(:red)
        exit 1
      end

      # Present service discovery results
      def present_service_discovery_result(discovered_services:, method:)
        puts "🔍 Service Discovery Results".colorize(:yellow)
        puts "Discovery Method: #{method}"
        puts "Discovered Services: #{discovered_services.join(', ')}"
      end
    end
  end
end
