# Console presenter for displaying results in terminal output
# Provides formatted output for development and testing

require 'colorize'

module Interfaces
  module Presenters
    class ConsolePresenter
      # Present label dispatch results
      def present_label_dispatch_result(deploy_labels:, labels_added:, labels_removed:, changed_files:)
        print_lines(TextFormat.label_dispatch(deploy_labels: deploy_labels, labels_added: labels_added, labels_removed: labels_removed, changed_files: changed_files), heading_color: :blue)
      end

      # Present deployment matrix results
      def present_deployment_matrix(deployment_targets:, deploy_labels:, target_environments:, pr_number:)
        print_lines(TextFormat.deployment_matrix(deployment_targets: deployment_targets, deploy_labels: deploy_labels, target_environments: target_environments, pr_number: pr_number), heading_color: :green)
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

      def present_config_details(config:)
        print_lines(TextFormat.config_details(config: config))
      end

      def present_service_test_result(service_name:, matches:)
        print_lines(TextFormat.service_test_result(service_name: service_name, matches: matches))
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
      def present_error(message)
        puts "❌ Error: #{message}".colorize(:red)
      end

      # Present service discovery results
      def present_service_discovery_result(discovered_services:, method:)
        puts "🔍 Service Discovery Results".colorize(:yellow)
        puts "Discovery Method: #{method}"
        puts "Discovered Services: #{discovered_services.join(', ')}"
      end

      private

      def print_lines(lines, heading_color: nil)
        heading, *rest = lines
        puts heading_color ? heading.colorize(heading_color) : heading
        rest.each { |line| puts line }
      end
    end
  end
end
