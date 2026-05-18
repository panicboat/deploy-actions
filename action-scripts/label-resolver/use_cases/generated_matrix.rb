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

        # A service can legitimately span multiple conventions (e.g. aws/{service} for
        # terragrunt + kubernetes/components/{service} for kubernetes manifests).
        # Collect stacks from every matching convention; dedup by stack name (first wins)
        # so duplicate stack names across conventions don't multiply targets — downstream
        # lookup is keyed on stack name and converges to the same working directory.
        matching_conventions = find_matching_conventions(deploy_label.service, config)
        return targets if matching_conventions.empty?

        stacks = matching_conventions.flat_map { |c| c['stacks'] || [] }.uniq { |s| s['name'] }

        stacks.each do |stack_config|
          stack_name = stack_config['name']
          stack_directory = stack_config['directory']

          # Check if stack is environment-specific (contains {environment} placeholder)
          is_environment_specific = stack_directory&.include?('{environment}')

          if is_environment_specific
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
                targets << target if target
              end
            end
          else
            # Environment-agnostic stack - generate only one target with nil environment
            # Check if stack directory exists (use first environment for validation)
            first_env = @target_environments.first
            if stack_directory_exists?(deploy_label.service, first_env, stack_name, config)
              target = generate_deployment_target(deploy_label, nil, stack_name, config)
              targets << target if target
            end
          end
        end

        targets
      end

      # Find every convention that has existing directories for this service.
      # Returns conventions in declaration order so callers can rely on first-wins dedup
      # for stack names that appear in more than one convention.
      def find_matching_conventions(service_name, config)
        repo_root = find_repository_root

        config.stack_conventions_config.select do |convention|
          stacks = convention['stacks'] || []

          stacks.any? do |stack_config|
            @target_environments.any? do |env|
              root_pattern = convention['root']
              stack_directory = stack_config['directory']

              full_pattern = if root_pattern.nil? || root_pattern.empty?
                              stack_directory
                            else
                              "#{root_pattern}/#{stack_directory}"
                            end

              values = { 'service' => service_name }
              values['environment'] = env if full_pattern.include?('{environment}')

              expanded_pattern = begin
                Entities::PatternMatcher.expand(full_pattern, values)
              rescue Entities::UnresolvedPlaceholderError
                # Pattern has arbitrary placeholders; replace unknowns with "*" and glob.
                glob_pat = full_pattern.gsub(Entities::PatternMatcher::PLACEHOLDER_REGEX) do
                  name = Regexp.last_match(1)
                  values.key?(name) ? values[name] : '*'
                end
                matches = Dir.glob(glob_pat, base: repo_root).select do |rel|
                  File.directory?(File.join(repo_root, rel))
                end
                next matches.any?
              end

              File.directory?(File.join(repo_root, expanded_pattern))
            end
          end
        end
      end

      # Check if stack directory exists for service/environment combination
      def stack_directory_exists?(service_name, environment, stack, config)
        dir_patterns = config.stack_conventions_for(service_name, stack)
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
          dir_patterns = config.stack_conventions_for(service_name, stack_name)
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
        if service_config && service_config['stack_conventions']
          service_config['stack_conventions'].each do |stack, pattern|
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
        dir_patterns = config.stack_conventions_for(deploy_label.service, stack)
        return nil if dir_patterns.empty?

        working_dir = nil
        matched_dir_pattern = nil
        repo_root = find_repository_root

        dir_patterns.each do |dir_pattern|
          candidate_dir = expand_directory_pattern(dir_pattern, deploy_label.service, target_environment)
          next unless candidate_dir

          full_path = File.join(repo_root, candidate_dir)
          if File.directory?(full_path)
            working_dir = candidate_dir
            matched_dir_pattern = dir_pattern
            break
          end
        end

        return nil unless working_dir

        full_match_pattern = full_pattern_for(deploy_label.service, matched_dir_pattern, config)
        captures = extract_captures(full_match_pattern, working_dir)

        create_deployment_target(deploy_label, target_environment, stack, working_dir, config, captures)
      end

      # Find the full (root + "/" + directory) pattern that produced this
      # matched dir_pattern. Used to recover captures from working_dir.
      def full_pattern_for(service_name, dir_pattern, config)
        config.stack_conventions_config.each do |convention|
          (convention['stacks'] || []).each do |stack_config|
            next unless stack_config['directory'] == dir_pattern

            root_pattern = convention['root']
            return root_pattern.nil? || root_pattern.empty? ? dir_pattern : "#{root_pattern}/#{dir_pattern}"
          end
        end

        # Service-specific stack_conventions fallback (services[].stack_conventions)
        service_config = config.services[service_name]
        if service_config && service_config['stack_conventions']
          service_config['stack_conventions'].each_value do |pattern|
            return pattern if pattern == dir_pattern
          end
        end

        dir_pattern
      end

      # Build the captures map for one target. Drops {service} and
      # {environment} since they map to dedicated DeploymentTarget fields.
      # Raises if the working_dir doesn't match the pattern (invariant
      # violation: the pattern was used to build the path moments ago).
      def extract_captures(full_match_pattern, working_dir)
        return {} unless full_match_pattern

        raw = Entities::PatternMatcher.extract(full_match_pattern, working_dir)
        if raw.nil?
          raise "PatternMatcher.extract returned nil for pattern '#{full_match_pattern}' and working_dir '#{working_dir}'"
        end

        raw.reject { |k, _| k == 'service' || k == 'environment' }
      end

      # Create deployment target (unified across stacks)
      def create_deployment_target(deploy_label, target_environment, stack, working_dir, config, captures = {})
        Entities::DeploymentTarget.new(
          service: deploy_label.service,
          environment: target_environment,
          stack: stack,
          working_directory: working_dir,
          stack_convention_root: extract_root_from_working_dir(working_dir, deploy_label.service, target_environment, config),
          attributes: target_environment ? config.stack_attributes_for(target_environment, stack) : {},
          captures: captures
        )
      end

      # Expand directory pattern with placeholders. Delegates to PatternMatcher
      # so all placeholder rules live in one place. Builds the values map
      # conditionally because {environment} is optional for env-agnostic stacks.
      # For patterns with arbitrary placeholders (e.g. {team}), replaces unknown
      # segments with "*" and uses Dir.glob to find the matching directory on disk.
      def expand_directory_pattern(pattern, service_name, target_environment)
        return nil unless pattern

        values = { 'service' => service_name }
        if pattern.include?('{environment}')
          if target_environment.nil?
            raise Entities::UnresolvedPlaceholderError,
                  "{environment} appears in pattern '#{pattern}' but target_environment is nil"
          end
          values['environment'] = target_environment
        end

        begin
          Entities::PatternMatcher.expand(pattern, values)
        rescue Entities::UnresolvedPlaceholderError
          # Pattern contains arbitrary placeholders beyond {service}/{environment}.
          # Replace unknown placeholders with "*" and resolve via Dir.glob.
          glob_pattern = pattern.gsub(Entities::PatternMatcher::PLACEHOLDER_REGEX) do
            name = Regexp.last_match(1)
            values.key?(name) ? values[name] : '*'
          end
          repo_root = find_repository_root
          matches = Dir.glob(glob_pattern, base: repo_root).select do |rel|
            File.directory?(File.join(repo_root, rel))
          end
          return nil if matches.empty?

          matches.first
        end
      end

      # Extract root directory from working directory based on configuration
      def extract_root_from_working_dir(working_dir, service_name, target_environment, config)
        # Try to match working_dir against all possible patterns to find the root
        config.stack_conventions_config.each do |convention|
          root_pattern = convention['root']
          stacks = convention['stacks'] || []

          stacks.each do |stack_config|
            full_pattern = if root_pattern.nil? || root_pattern.empty?
                            stack_config['directory']
                          else
                            "#{root_pattern}/#{stack_config['directory']}"
                          end

            begin
              expanded_pattern = expand_directory_pattern(full_pattern, service_name, target_environment)
            rescue Entities::UnresolvedPlaceholderError
              # Convention requires {environment} but target_environment is nil
              # for this call. Skip this convention and let another match.
              next
            end
            next unless expanded_pattern

            if working_dir == expanded_pattern
              # full_pattern matched, so root_pattern (its prefix) is guaranteed
              # to expand with the same values. expand_directory_pattern never
              # returns nil for a non-nil pattern.
              return expand_directory_pattern(root_pattern || '', service_name, target_environment)
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
