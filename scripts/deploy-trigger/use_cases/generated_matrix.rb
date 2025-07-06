# Use case for generating deployment matrix from deploy labels
# Creates deployment targets with all necessary configuration

module UseCases
  module DeployTrigger
    class GenerateMatrix
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute matrix generation from deploy labels
      def execute(deploy_labels:, target_environment: nil)
        config = @config_client.load_workflow_config

        # If target_environment is not provided, use 'develop' as default
        target_environment ||= 'develop'

        deployment_targets = []

        deploy_labels.each do |deploy_label|
          next unless deploy_label.valid?

          # Check if service is excluded from automation
          if service_excluded_from_automation?(deploy_label.service, config)
            puts "⚠️  Skipping matrix generation for excluded service: #{deploy_label.service}"
            next
          end

          # Get available stacks by checking directory existence
          available_stacks = detect_available_stacks(deploy_label.service, target_environment, config)

          # Generate targets for each available stack
          available_stacks.each do |stack|
            target = generate_deployment_target(deploy_label, target_environment, stack, config)
            deployment_targets << target if target&.valid?
          end
        end

        Entities::Result.success(
          deployment_targets: deployment_targets,
          has_deployments: deployment_targets.any?,
          total_targets: deployment_targets.length
        )
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end

      private

      # Check if service is excluded from automation
      def service_excluded_from_automation?(service_name, config)
        service_config = config.services[service_name]
        return false unless service_config

        # Basic exclusion check: exclude_from_automation: true
        service_config['exclude_from_automation'] == true
      end

      # Detect available stacks by checking directory existence
      def detect_available_stacks(service_name, target_environment, config)
        # Skip stack detection for excluded services
        if service_excluded_from_automation?(service_name, config)
          return []
        end

        available_stacks = []

        # Get repository root by finding .git directory
        repo_root = find_repository_root

        # Check all configured directory conventions
        config.directory_conventions.each do |stack, pattern|
          # Get directory path by expanding placeholders
          dir_path = expand_directory_pattern(pattern, service_name, target_environment)
          next unless dir_path

          # Resolve path relative to repository root
          full_path = File.join(repo_root, dir_path)

          # Check if directory exists
          if File.directory?(full_path)
            available_stacks << stack
          end
        end

        # Also check service-specific directory conventions
        service_config = config.services[service_name]
        if service_config && service_config['directory_conventions']
          service_config['directory_conventions'].each do |stack, pattern|
            # Get directory path by expanding placeholders
            dir_path = expand_directory_pattern(pattern, service_name, target_environment)
            next unless dir_path

            # Resolve path relative to repository root
            full_path = File.join(repo_root, dir_path)

            # Check if directory exists and not already added
            if File.directory?(full_path) && !available_stacks.include?(stack)
              available_stacks << stack
            end
          end
        end

        available_stacks
      end

      # Generate a deployment target from deploy label, environment, and stack
      def generate_deployment_target(deploy_label, target_environment, stack, config)
        env_config = config.environment_config(target_environment)

        # Get directory convention and expand placeholders
        dir_pattern = config.directory_convention_for(deploy_label.service, stack)
        return nil unless dir_pattern

        # Expand placeholders
        working_dir = expand_directory_pattern(dir_pattern, deploy_label.service, target_environment)
        return nil unless working_dir

        # Get repository root path for absolute path checking
        repo_root = find_repository_root
        full_path = File.join(repo_root, working_dir)

        # Double-check directory exists (safety check)
        unless File.directory?(full_path)
          puts "Warning: Directory does not exist: #{full_path}"
          return nil
        end

        # Create deployment target with appropriate configuration based on stack
        case stack
        when 'terragrunt'
          create_terragrunt_target(deploy_label, target_environment, env_config, working_dir)
        when 'kubernetes'
          create_kubernetes_target(deploy_label, target_environment, env_config, working_dir)
        else
          # Generic target for future stacks
          create_generic_target(deploy_label, target_environment, stack, env_config, working_dir)
        end
      end

      # Create Terragrunt deployment target
      def create_terragrunt_target(deploy_label, target_environment, env_config, working_dir)
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: 'terragrunt',
          iam_role_plan: env_config['iam_role_plan'],
          iam_role_apply: env_config['iam_role_apply'],
          aws_region: env_config['aws_region'],
          working_directory: working_dir
        )
      end

      # Create Kubernetes deployment target
      def create_kubernetes_target(deploy_label, target_environment, env_config, working_dir)
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: 'kubernetes',
          aws_region: env_config['aws_region'],
          working_directory: working_dir
        )
      end

      # Create generic deployment target for future stacks
      def create_generic_target(deploy_label, target_environment, stack, env_config, working_dir)
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: stack,
          iam_role_plan: env_config['iam_role_plan'],
          iam_role_apply: env_config['iam_role_apply'],
          aws_region: env_config['aws_region'],
          working_directory: working_dir
        )
      end

      # Expand directory pattern with placeholders
      def expand_directory_pattern(pattern, service_name, target_environment)
        return nil unless pattern

        # Expand both service and environment placeholders
        expanded = pattern
          .gsub('{service}', service_name)
          .gsub('{environment}', target_environment)

        # Validate that all placeholders were replaced
        if expanded.include?('{') && expanded.include?('}')
          puts "Warning: Unresolved placeholders in pattern: #{pattern} -> #{expanded}"
          return nil
        end

        expanded
      end

      # Find repository root by looking for .git directory
      def find_repository_root(start_path = __dir__)
        current_path = File.expand_path(start_path)

        loop do
          # Check if .git directory exists
          git_path = File.join(current_path, '.git')
          return current_path if File.directory?(git_path) || File.file?(git_path)

          # Move up one directory
          parent_path = File.dirname(current_path)

          # Stop if we've reached the root directory
          break if parent_path == current_path

          current_path = parent_path
        end

        # Fallback: if .git not found, raise error with helpful message
        raise "Could not find repository root (.git directory) starting from #{start_path}. " \
              "Make sure this script is run within a Git repository."
      end
    end
  end
end
