# Controller for configuration management functionality
# Handles configuration validation, loading, and diagnostic operations

module Interfaces
  module Controllers
    class ConfigManagerController
      def initialize(
        validate_config_use_case:,
        resolve_environments_use_case:,
        enumerate_targets_use_case:,
        config_client:,
        presenter:
      )
        @validate_config = validate_config_use_case
        @resolve_environments = resolve_environments_use_case
        @enumerate_targets = enumerate_targets_use_case
        @config_client = config_client
        @presenter = presenter
      end

      # Validate configuration file
      def validate_configuration
        validation_result = @validate_config.execute

        if validation_result.success?
          validation = validation_result.value
          @presenter.present_config_validation_result(
            valid: true,
            config: validation.config,
            summary: validation.summary
          )
          validation_result
        else
          @presenter.present_config_validation_result(
            valid: false,
            errors: [validation_result.error_message]
          )
          # TODO: return the failure so that an invalid configuration exits 1.
          Entities::Result.success
        end
      end

      # Show parsed configuration in readable format
      def show_configuration
        begin
          config = @config_client.load_workflow_config
          @presenter.present_config_details(config: config)
          Entities::Result.success(config)
        rescue => error
          failure(Entities::Result.failure("Failed to load configuration: #{error.message}"))
        end
      end

      def test_service_configuration(service_name:, environment: nil)
        config = @config_client.load_workflow_config
        environments = @resolve_environments.execute(config: config, requested: environment && [environment])
        return failure(environments) if environments.failure?

        candidates = @enumerate_targets.execute(config: config, services: [service_name], environments: environments.value)
        return failure(candidates) if candidates.failure?

        matches = candidates.value.map { |candidate| { target: candidate.to_deployment_target, excluded: candidate.excluded? } }
        @presenter.present_service_test_result(service_name: service_name, matches: matches)
        Entities::Result.success(matches)
      rescue => error
        failure(Entities::Result.failure("Failed to test service configuration: #{error.message}"))
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
            validation_result.error_message
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
        Entities::Result.success(diagnostic_results)
      end

      # Generate configuration template
      def generate_config_template
        template = build_config_template
        @presenter.present_config_template(template: template)
        Entities::Result.success(template)
      end

      private

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end

      def build_config_template
        <<~YAML
          profiles:
            aws-develop:
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::123456789012:role/github-oidc-auth-develop-github-actions-plan-role
              iam_role_apply: arn:aws:iam::123456789012:role/github-oidc-auth-develop-github-actions-apply-role
            aws-production:
              aws_region: ap-northeast-1
              iam_role_plan: arn:aws:iam::123456789012:role/github-oidc-auth-production-github-actions-plan-role
              iam_role_apply: arn:aws:iam::123456789012:role/github-oidc-auth-production-github-actions-apply-role

          services:
            - id: app
              roots:
                - "dystopia/{service}"
                - "system-components/{service}"
              ignore:
                - "**/README.md"
              stacks:
                - id: dockerfile
                  path: "."
                  attributes:
                    type: container
                    repository: registry.example.com/{service}
                - id: kustomize
                  path: "kubernetes/overlays/{environment}"
                  attributes:
                    type: kustomize
                - id: aws
                  path: "infrastructure/aws/{environment}"
                  attributes:
                    type: terragrunt
                  environments:
                    develop:
                      use: [aws-develop]
                    production:
                      use: [aws-production]
                  exclude:
                    - environment: production
        YAML
      end
    end
  end
end
