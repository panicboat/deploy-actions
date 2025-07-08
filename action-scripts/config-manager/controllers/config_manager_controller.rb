# Controller for configuration management functionality
# Handles configuration validation, loading, and diagnostic operations

module Interfaces
  module Controllers
    class ConfigManagerController
      def initialize(
        validate_config_use_case:,
        config_client:,
        presenter:
      )
        @validate_config = validate_config_use_case
        @config_client = config_client
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

      # Test service configuration for specific service and environment
      def test_service_configuration(service_name:, environment:)
        begin
          config = @config_client.load_workflow_config

          # Validate service exists
          unless config.services.key?(service_name)
            return @presenter.present_error(
              Entities::Result.failure(error_message: "Service '#{service_name}' not found in configuration")
            )
          end

          # Validate environment exists
          unless config.environments.key?(environment)
            return @presenter.present_error(
              Entities::Result.failure(error_message: "Environment '#{environment}' not found in configuration")
            )
          end

          # Get environment and service configurations
          env_config = config.environment_config(environment)
          service_config = config.services[service_name]

          # Test directory conventions
          terragrunt_dir = config.directory_convention_for(service_name, 'terragrunt')
            &.gsub('{service}', service_name)
            &.gsub('{environment}', environment)

          kubernetes_dir = config.directory_convention_for(service_name, 'kubernetes')
            &.gsub('{service}', service_name)
            &.gsub('{environment}', environment)

          @presenter.present_service_test_result(
            service_name: service_name,
            environment: environment,
            env_config: env_config,
            service_config: service_config,
            terragrunt_directory: terragrunt_dir,
            kubernetes_directory: kubernetes_dir
          )
        rescue => error
          @presenter.present_error(
            Entities::Result.failure(error_message: "Failed to test service configuration: #{error.message}")
          )
        end
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

      # Build a configuration template with examples
      def build_config_template
        <<~YAML
          # Workflow Automation Configuration Template
          # Generated by config-manager

          environments:
            - environment: develop
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-develop-plan-role
              iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-develop-apply-role

            - environment: staging
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-staging-plan-role
              iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-staging-apply-role

            - environment: production
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-production-plan-role
              iam_role_apply: arn:aws:iam::ACCOUNT_ID:role/github-oidc-auth-production-apply-role

          directory_conventions:
            root: "{service}"
            stacks:
              - name: terragrunt
                directory: "terragrunt/{environment}"
              - name: kubernetes
                directory: "kubernetes/overlays/{environment}"

          services:
            - name: example-service
              directory_conventions:
                terragrunt: "services/{service}/terragrunt/envs/{environment}"
                kubernetes: "services/{service}/kubernetes/overlays/{environment}"
            
            - name: excluded-service
              exclude_from_automation: true
              exclusion_config:
                reason: "Manual deployment required due to special requirements"
                type: "permanent"

          branch_patterns:
            develop: develop
            staging: staging
            production: production
        YAML
      end
    end
  end
end
