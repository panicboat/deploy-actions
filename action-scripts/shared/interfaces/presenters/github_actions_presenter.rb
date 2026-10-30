# GitHub Actions presenter for formatting output for GitHub Actions workflows

module Interfaces
  module Presenters
    class GitHubActionsPresenter
      def initialize(output_path:)
        @output_path = output_path
      end

      # Present label dispatch results for GitHub Actions
      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:)
        write_outputs(
          'labels-added' => labels_added.to_json,
          'labels-removed' => labels_removed.to_json,
          'services-detected' => deploy_labels.map(&:service).uniq.to_json,
          'has-changes' => deploy_labels.any?.to_s,
        )

        puts TextFormat.label_dispatch(deploy_labels: deploy_labels, labels_added: labels_added, labels_removed: labels_removed, changed_files: changed_files)
      end

      # Present deployment matrix for GitHub Actions
      def present_deployment_matrix(**fields)
        deployment_targets = fields.fetch(:deployment_targets)
        write_outputs(
          'targets' => deployment_targets.map(&:to_matrix_item).to_json,
          'has-targets' => deployment_targets.any?.to_s,
          'safety-status' => fields[:safety_status]
        )

        puts TextFormat.deployment_matrix(**fields)
      end

      # Present configuration validation results for GitHub Actions
      def present_config_validation_result(valid:, errors: [], config: nil, summary: nil)
        write_outputs('config_valid' => valid.to_s)

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

      def present_config_details(config:)
        puts TextFormat.config_details(config: config)
      end

      def present_service_test_result(service_name:, matches:)
        puts TextFormat.service_test_result(service_name: service_name, matches: matches)
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
      def present_error(message)
        puts "::error::#{message}"
      end

      # Present service discovery results
      def present_service_discovery_result(discovered_services:, method:)
        puts "🔍 Service Discovery Results"
        puts "Discovery Method: #{method}"
        puts "Discovered Services: #{discovered_services.join(', ')}"
      end

      private

      def write_outputs(outputs)
        raise 'GITHUB_OUTPUT is not set' if @output_path.nil?

        File.open(@output_path, 'a') do |file|
          outputs.each { |key, value| file.puts "#{key}=#{value}" }
        end
      end
    end
  end
end
