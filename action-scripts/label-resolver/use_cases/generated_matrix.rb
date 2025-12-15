# Use case for generating deployment matrix from deploy labels
# Creates deployment targets with all necessary configuration

module UseCases
  module LabelResolver
    class GenerateMatrix
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute matrix generation from deploy labels
      def execute(deploy_labels:, target_environments:)
        @target_environments = target_environments
        config = @config_client.load_workflow_config

        # Validate all target_environments exist
        target_environments.each do |env|
          env_config = config.environment_config(env)
          unless env_config
            return Entities::Result.failure(
              error_message: "Environment configuration not found for: #{env}"
            )
          end
        end

        deployment_targets = []

        deploy_labels.each do |deploy_label|
          next unless deploy_label.valid?

          # Handle deploy:all - expand to all non-excluded services
          if deploy_label.service == 'all'
            all_services = config.services.keys.reject do |service_name|
              config.excluded_services.include?(service_name)
            end

            all_services.each do |service_name|
              service_label = Entities::DeployLabel.from_service(service: service_name)
              targets_for_service = generate_targets_for_service(service_label, config)
              deployment_targets.concat(targets_for_service)
            end
          else
            # Check if service is excluded from automation
            if service_excluded_from_automation?(deploy_label.service, config)
              next
            end

            # Generate targets for the service using stack-specific targets
            targets_for_service = generate_targets_for_service(deploy_label, config)
            deployment_targets.concat(targets_for_service)
          end
        end

        Entities::Result.success(
          deployment_targets: deployment_targets,
          has_deployments: deployment_targets.any?,
          total_targets: deployment_targets.length
        )
      rescue => error
        puts "❌ Matrix generation failed: #{error.message}"
        puts "Error backtrace:"
        puts error.backtrace.first(10).join("\n")
        Entities::Result.failure(error_message: "Matrix generation failed: #{error.message}")
      end

      private

      # Generate deployment targets for a service across all applicable environments and stacks
      def generate_targets_for_service(deploy_label, config)
        targets = []

        # Get all available stacks from the first matching convention only
        matching_convention = find_matching_convention(deploy_label.service, config)
        return targets unless matching_convention

        stacks = matching_convention['stacks'] || []

        stacks.each do |stack_config|
          stack_name = stack_config['name']

          # Generate targets for all target environments
          @target_environments.each do |env|
            # Validate that the target environment exists
            env_config = config.environment_config(env)
            unless env_config
              puts "Warning: Environment configuration not found for: #{env}"
              next
            end

            # Check if stack directory exists for this service/environment combination
            if stack_directory_exists?(deploy_label.service, env, stack_name, config)
              target = generate_deployment_target(deploy_label, env, stack_name, config)
              targets << target if target&.valid?
            end
          end
        end

        targets
      end

      # Find the first matching convention that has existing directories for this service
      def find_matching_convention(service_name, config)
        repo_root = find_repository_root

        config.directory_conventions_config.each do |convention|
          # Check if any stack in this convention has existing directories for this service
          stacks = convention['stacks'] || []

          has_existing_directory = stacks.any? do |stack_config|
            stack_name = stack_config['name']

            # Check across all target environments
            @target_environments.any? do |env|
              # Build the pattern for this convention
              root_pattern = convention['root']
              stack_directory = stack_config['directory']

              full_pattern = if root_pattern.nil? || root_pattern.empty?
                              stack_directory
                            else
                              "#{root_pattern}/#{stack_directory}"
                            end

              # Expand placeholders
              expanded_pattern = full_pattern.gsub('{service}', service_name)
              # Only expand {environment} placeholder if present
              if full_pattern.include?('{environment}')
                expanded_pattern = expanded_pattern.gsub('{environment}', env)
              end

              # Check if directory exists
              full_path = File.join(repo_root, expanded_pattern)
              File.directory?(full_path)
            end
          end

          return convention if has_existing_directory
        end

        nil
      end

      # Check if stack directory exists for service/environment combination
      def stack_directory_exists?(service_name, environment, stack, config)
        dir_patterns = config.directory_conventions_for(service_name, stack)
        return false if dir_patterns.empty?

        repo_root = find_repository_root

        dir_patterns.any? do |dir_pattern|
          dir_path = expand_directory_pattern(dir_pattern, service_name, environment)
          next false unless dir_path

          full_path = File.join(repo_root, dir_path)
          File.directory?(full_path)
        end
      end

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
        puts "🔍 Current working directory: #{Dir.pwd}"
        puts "🔍 Script directory (__dir__): #{__dir__}"
        repo_root = find_repository_root
        puts "🔍 Repository root detected: #{repo_root}"

        # Check all configured stacks using hierarchical structure
        stacks = config.send(:directory_stacks) || []
        stacks.each do |stack_config|
          stack_name = stack_config['name']
          next unless stack_name

          # Get all possible directory patterns for this service and stack
          dir_patterns = config.directory_conventions_for(service_name, stack_name)
          next if dir_patterns.empty?

          # Check each possible directory pattern
          dir_patterns.each do |dir_pattern|
            # Get directory path by expanding placeholders
            dir_path = expand_directory_pattern(dir_pattern, service_name, target_environment)
            next unless dir_path

            # Resolve path relative to repository root
            full_path = File.join(repo_root, dir_path)
            puts "🔍 Checking directory: #{full_path}"

            # Check if directory exists
            if File.directory?(full_path)
              puts "✅ Found #{stack_name} stack for #{service_name}:#{target_environment}"
              available_stacks << stack_name
              break # Found one, no need to check other patterns for this stack
            else
              puts "❌ Directory not found: #{full_path}"
            end
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

        # Get all possible directory patterns and find the first existing one
        dir_patterns = config.directory_conventions_for(deploy_label.service, stack)
        return nil if dir_patterns.empty?

        working_dir = nil
        repo_root = find_repository_root

        # Try each pattern until we find an existing directory
        dir_patterns.each do |dir_pattern|
          # Expand placeholders
          candidate_dir = expand_directory_pattern(dir_pattern, deploy_label.service, target_environment)
          next unless candidate_dir

          # Check if directory exists
          full_path = File.join(repo_root, candidate_dir)
          if File.directory?(full_path)
            working_dir = candidate_dir
            break
          end
        end

        return nil unless working_dir

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
        config = @config_client.load_workflow_config
        directory_conventions_root = extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config)

        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: 'terragrunt',
          iam_role_plan: env_config['iam_role_plan'],
          iam_role_apply: env_config['iam_role_apply'],
          aws_region: env_config['aws_region'],
          working_directory: working_dir,
          directory_conventions_root: directory_conventions_root
        )
      end

      # Create Kubernetes deployment target
      def create_kubernetes_target(deploy_label, target_environment, env_config, working_dir)
        config = @config_client.load_workflow_config
        directory_conventions_root = extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config)

        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: 'kubernetes',
          aws_region: env_config['aws_region'],
          working_directory: working_dir,
          directory_conventions_root: directory_conventions_root
        )
      end

      # Create generic deployment target for future stacks
      def create_generic_target(deploy_label, target_environment, stack, env_config, working_dir)
        config = @config_client.load_workflow_config
        directory_conventions_root = extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config)

        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: stack,
          working_directory: working_dir,
          directory_conventions_root: directory_conventions_root
        )
      end

      # Expand directory pattern with placeholders
      def expand_directory_pattern(pattern, service_name, target_environment)
        return nil unless pattern

        # Expand service placeholder
        expanded = pattern.gsub('{service}', service_name)
        # Only expand {environment} placeholder if present (supports environment-agnostic stacks)
        if pattern.include?('{environment}')
          expanded = expanded.gsub('{environment}', target_environment)
        end

        # Validate that all placeholders were replaced
        if expanded.include?('{') && expanded.include?('}')
          puts "Warning: Unresolved placeholders in pattern: #{pattern} -> #{expanded}"
          return nil
        end

        expanded
      end

      # Extract root directory from working directory based on configuration
      def extract_root_from_working_dir(working_dir, service_name, target_environment, config)
        # Try to match working_dir against all possible patterns to find the root
        config.directory_conventions_config.each do |convention|
          root_pattern = convention['root']
          stacks = convention['stacks'] || []

          stacks.each do |stack_config|
            # Build the full pattern: root + stack directory
            full_pattern = if root_pattern.nil? || root_pattern.empty?
                            stack_config['directory']
                          else
                            "#{root_pattern}/#{stack_config['directory']}"
                          end

            # Expand placeholders
            expanded_pattern = full_pattern
              .gsub('{service}', service_name)
              .gsub('{environment}', target_environment)

            # Check if working_dir matches this pattern
            if working_dir == expanded_pattern
              # Found a match, extract the root part
              expanded_root = root_pattern
                .gsub('{service}', service_name)
                .gsub('{environment}', target_environment)
              return expanded_root
            end
          end
        end

        # Fallback: if no pattern matches, try to extract service name
        # This handles service-specific directory conventions
        service_name
      end

      # Find repository root by looking for .git directory
      def find_repository_root(start_path = __dir__)
        puts "🔍 SOURCE_REPO_PATH env var: #{ENV['SOURCE_REPO_PATH'].inspect}"

        # Check if SOURCE_REPO_PATH environment variable is set (for composite actions)
        if ENV['SOURCE_REPO_PATH'] && !ENV['SOURCE_REPO_PATH'].empty?
          source_repo_path = File.expand_path(ENV['SOURCE_REPO_PATH'], __dir__)
          puts "🔍 Expanded source_repo_path: #{source_repo_path}"
          puts "🔍 Directory exists: #{File.directory?(source_repo_path)}"

          if File.directory?(source_repo_path)
            git_path = File.join(source_repo_path, '.git')
            puts "🔍 Checking git path: #{git_path}"
            puts "🔍 Git directory exists: #{File.directory?(git_path) || File.file?(git_path)}"

            if File.directory?(git_path) || File.file?(git_path)
              puts "✅ Using SOURCE_REPO_PATH as repository root: #{source_repo_path}"
              return source_repo_path
            else
              puts "❌ No .git found in SOURCE_REPO_PATH, falling back to default search"
            end
          else
            puts "❌ SOURCE_REPO_PATH directory does not exist, falling back to default search"
          end
        else
          puts "❌ SOURCE_REPO_PATH not set or empty, using default .git search"
        end

        puts "❌ SOURCE_REPO_PATH not found, unable to locate source repository"

        # Default behavior: search for .git directory
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
              "Make sure this script is run within a Git repository or set SOURCE_REPO_PATH environment variable."
      end
    end
  end
end
