# Controller for configuration management functionality
# Handles configuration validation, loading, and diagnostic operations

module Interfaces
  module Controllers
    class ConfigManagerController
      def initialize(
        validate_config_use_case:,
        config_client:,
        file_client:,
        presenter:
      )
        @validate_config = validate_config_use_case
        @config_client = config_client
        @file_client = file_client
        @presenter = presenter
      end

      # Validate configuration file
      def validate_configuration
        validation_result = @validate_config.execute

        if validation_result.success?
          @presenter.present_config_validation_result(
            valid: true,
            config: validation_result.config,
            summary: validation_result.validation_summary
          )
        else
          @presenter.present_config_validation_result(
            valid: false,
            errors: validation_result.validation_errors || [validation_result.error_message]
          )
        end
      end

      # Show parsed configuration in readable format
      def show_configuration
        begin
          config = @config_client.load_workflow_config
          @presenter.present_config_details(config: config)
        rescue => error
          @presenter.present_error(
            Entities::Result.failure(error_message: "Failed to load configuration: #{error.message}")
          )
        end
      end

      def test_service_configuration(service_name:, environment: nil)
        config = @config_client.load_workflow_config
        if environment && !config.environment_names.include?(environment)
          return @presenter.present_error(Entities::Result.failure(error_message: "Environment '#{environment}' not found in configuration"))
        end
        candidates = {}
        config.stacks.each do |stack|
          environments = stack.key?('environments') ? stack['environments'].keys : [nil]
          environments &= [environment] if environment && stack.key?('environments')
          environments.each do |selected|
            values = { 'service' => service_name, 'environment' => selected }
            stack['paths'].each do |pattern|
              @file_client.resolve_directories(pattern: pattern, values: values).each do |match|
                captures = match.fetch(:captures)
                next if captures.fetch('service').start_with?('.')
                directory = match.fetch(:working_directory)
                custom = captures.reject { |key, _| %w[service environment].include?(key) }
                identity = [service_name, stack['id'], selected, directory]
                if candidates.key?(identity) && candidates[identity][:captures] != custom
                  raise "Conflicting captures for stack '#{stack['id']}' at '#{directory}'"
                end
                candidates[identity] = { stack: stack, environment: selected, working_directory: directory, captures: custom }
              end
            end
          end
        end
        matches = candidates.values.map do |candidate|
          stack = candidate.fetch(:stack)
          selected = candidate.fetch(:environment)
          captures = candidate.fetch(:captures)
          attributes = stack.key?('environments') ? stack['environments'].fetch(selected) : stack['attributes']
          target = Entities::DeploymentTarget.new(service: service_name, environment: selected, stack: stack['name'], stack_id: stack['id'], working_directory: candidate.fetch(:working_directory), attributes: attributes, captures: captures)
          { target: target, excluded: config.excluded?(stack, captures.merge('service' => service_name, 'environment' => selected)) }
        end
        @presenter.present_service_test_result(service_name: service_name, matches: matches)
      rescue => error
        @presenter.present_error(Entities::Result.failure(error_message: "Failed to test service configuration: #{error.message}"))
      end

      # Diagnostic check for configuration and environment
      def run_diagnostics
        puts "🔍 Running workflow automation diagnostics..."

        diagnostic_results = []

        # Check 1: Configuration file validation
        validation_result = @validate_config.execute
        diagnostic_results << {
          check: 'Configuration Validation',
          status: validation_result.success? ? 'PASS' : 'FAIL',
          details: validation_result.success? ?
            "Configuration is valid" :
            validation_result.validation_errors&.first || validation_result.error_message
        }

        # Check 2: Environment variables
        required_env_vars = %w[GITHUB_TOKEN GITHUB_REPOSITORY]
        env_check = required_env_vars.all? { |var| ENV[var] }
        diagnostic_results << {
          check: 'Environment Variables',
          status: env_check ? 'PASS' : 'FAIL',
          details: env_check ?
            "All required environment variables present" :
            "Missing: #{required_env_vars.reject { |var| ENV[var] }.join(', ')}"
        }

        # Check 3: Git repository status
        begin
          git_status = `git status --porcelain 2>/dev/null`
          git_clean = $?.success? && git_status.strip.empty?
          diagnostic_results << {
            check: 'Git Repository',
            status: git_clean ? 'PASS' : 'WARN',
            details: git_clean ?
              "Repository is clean" :
              "Repository has uncommitted changes"
          }
        rescue
          diagnostic_results << {
            check: 'Git Repository',
            status: 'WARN',
            details: "Could not check git status"
          }
        end

        # Check 4: Configuration file locations
        config_file_exists = File.exist?('workflow-config.yaml')
        diagnostic_results << {
          check: 'Configuration File',
          status: config_file_exists ? 'PASS' : 'FAIL',
          details: config_file_exists ?
            "Configuration file found at workflow-config.yaml" :
            "Configuration file not found at expected location"
        }

        @presenter.present_diagnostic_results(results: diagnostic_results)
      end

      # Generate configuration template
      def generate_config_template
        template = build_config_template
        @presenter.present_config_template(template: template)
      end

      private

      def build_config_template
        <<~YAML
          stacks:
            - name: terragrunt
              id: aws
              paths:
                - "dystopia/{service}/aws/{environment}"
                - "system-components/{service}/infrastructure/aws/{environment}"
              environments:
                develop:
                  aws_region: ap-northeast-1
                production:
                  aws_region: us-west-2
              exclude:
                - service: demo
                  environment: production
            - name: container
              paths:
                - "dystopia/{service}"
                - "system-components/{service}"
              attributes:
                repository: registry.example.com/app
        YAML
      end
    end
  end
end
