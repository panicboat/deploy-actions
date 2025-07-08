# Use case for validating workflow configuration
# Comprehensive validation of YAML configuration structure and content

module UseCases
  module ConfigManagement
    class ValidateConfig
      def initialize(config_client:)
        @config_client = config_client
      end

      # Execute configuration validation
      def execute
        begin
          config = @config_client.load_workflow_config
          validation_errors = []

          # Perform comprehensive validation
          validation_errors.concat(validate_environments(config))
          validation_errors.concat(validate_services(config))
          validation_errors.concat(validate_directory_conventions(config))
          validation_errors.concat(validate_branch_patterns(config))
          validation_errors.concat(validate_service_exclusions(config))

          if validation_errors.any?
            Entities::Result.failure(
              error_message: "Configuration validation failed with #{validation_errors.length} errors",
              validation_errors: validation_errors
            )
          else
            Entities::Result.success(
              valid: true,
              config: config,
              validation_summary: generate_validation_summary(config)
            )
          end
        rescue => error
          Entities::Result.failure(
            error_message: "Failed to load or validate configuration: #{error.message}",
            validation_errors: [error.message]
          )
        end
      end

      private

      # Validate environments configuration
      def validate_environments(config)
        errors = []
        environments = config.environments

        if environments.empty?
          errors << "No environments defined"
          return errors
        end

        required_envs = %w[develop staging production]
        missing_envs = required_envs - environments.keys
        errors.concat(missing_envs.map { |env| "Missing required environment: #{env}" })

        environments.each do |env_name, env_config|
          errors.concat(validate_environment_config(env_name, env_config))
        end

        errors
      end

      # Validate individual environment configuration
      def validate_environment_config(env_name, env_config)
        errors = []
        required_fields = %w[aws_region iam_role_plan iam_role_apply]

        required_fields.each do |field|
          unless env_config[field]
            errors << "Environment '#{env_name}' missing required field: #{field}"
          end
        end

        # Validate AWS region format
        if env_config['aws_region'] && !env_config['aws_region'].match(/^[a-z]{2}-[a-z]+-\d+$/)
          errors << "Environment '#{env_name}' has invalid AWS region format: #{env_config['aws_region']}"
        end

        # Validate IAM role ARN format
        %w[iam_role_plan iam_role_apply].each do |role_field|
          if env_config[role_field] && !env_config[role_field].start_with?('arn:aws:iam::')
            errors << "Environment '#{env_name}' has invalid IAM role ARN format for #{role_field}"
          end
        end

        errors
      end

      # Validate services configuration
      def validate_services(config)
        errors = []
        services = config.services

        services.each do |service_name, service_config|
          if service_name.start_with?('.')
            errors << "Service name cannot start with dot: #{service_name}"
          end

          if service_config['directory_conventions']
            service_config['directory_conventions'].each do |stack, pattern|
              unless pattern.include?('{service}')
                errors << "Service '#{service_name}' directory convention for '#{stack}' must include {service} placeholder"
              end
            end
          end
        end

        errors
      end

      # Validate directory conventions
      def validate_directory_conventions(config)
        errors = []
        conventions = config.directory_conventions

        if conventions.empty?
          errors << "No directory conventions defined"
          return errors
        end

        # Validate root pattern (can be empty string)
        unless conventions.key?('root')
          errors << "Directory conventions missing required 'root' field"
        end

        # Only validate {service} placeholder if root is not empty
        if conventions['root'] && !conventions['root'].empty? && !conventions['root'].include?('{service}')
          errors << "Directory conventions root must include {service} placeholder"
        end

        # Validate stacks
        stacks = conventions['stacks']
        unless stacks.is_a?(Array)
          errors << "Directory conventions 'stacks' must be an Array"
          return errors
        end

        if stacks.empty?
          errors << "Directory conventions 'stacks' cannot be empty"
          return errors
        end

        # Check for required stacks
        stack_names = stacks.map { |stack| stack['name'] }
        required_stacks = %w[terragrunt]
        missing_stacks = required_stacks - stack_names
        errors.concat(missing_stacks.map { |stack| "Missing required stack: #{stack}" })

        # Validate each stack
        stacks.each_with_index do |stack, index|
          unless stack['name']
            errors << "Stack at index #{index} missing required 'name' field"
          end

          unless stack['directory']
            errors << "Stack at index #{index} missing required 'directory' field"
          end

          if stack['directory'] && !stack['directory'].include?('{environment}')
            errors << "Stack '#{stack['name']}' directory must include {environment} placeholder"
          end
        end

        errors
      end

      # Validate branch patterns configuration
      def validate_branch_patterns(config)
        errors = []
        branch_patterns = config.branch_patterns

        required_patterns = %w[develop staging production]
        required_patterns.each do |pattern|
          unless branch_patterns[pattern]
            errors << "Missing branch pattern configuration: #{pattern}"
          end
        end

        # Validate that mapped environments exist
        branch_patterns.each do |branch_name, env_name|
          unless config.environments.key?(env_name)
            errors << "Branch pattern '#{branch_name}' references unknown environment: #{env_name}"
          end
        end

        errors
      end

      # Validate service exclusion configuration
      def validate_service_exclusions(config)
        errors = []
        services = config.services

        services.each do |service_name, service_config|
          if service_config['exclude_from_automation']
            errors.concat(validate_service_exclusion_config(service_name, service_config))
          end
        end

        errors
      end

      # Validate individual service exclusion configuration
      def validate_service_exclusion_config(service_name, service_config)
        errors = []

        # Check if exclusion is boolean true or valid object
        exclusion_setting = service_config['exclude_from_automation']
        unless [true, false].include?(exclusion_setting)
          errors << "Service '#{service_name}' exclude_from_automation must be boolean (true/false)"
          return errors
        end

        # If excluded, validate exclusion_config
        if exclusion_setting == true
          exclusion_config = service_config['exclusion_config']

          # exclusion_config is required when excluded
          if exclusion_config.nil?
            errors << "Service '#{service_name}' excluded from automation but missing exclusion_config"
            return errors
          end

          # Validate required fields in exclusion_config
          unless exclusion_config['reason']
            errors << "Service '#{service_name}' exclusion_config missing required field: reason"
          end

          # Validate exclusion type if provided
          if exclusion_config['type']
            valid_types = %w[permanent temporary conditional]
            unless valid_types.include?(exclusion_config['type'])
              errors << "Service '#{service_name}' exclusion_config type must be one of: #{valid_types.join(', ')}"
            end
          end

          # Check reason length (should be descriptive)
          if exclusion_config['reason'] && exclusion_config['reason'].length < 10
            errors << "Service '#{service_name}' exclusion_config reason should be more descriptive (at least 10 characters)"
          end

          unless service_config['directory_conventions']
            puts "INFO: Service '#{service_name}' is excluded and has no directory_conventions defined"
          end
        end

        errors
      end

      # Generate validation summary including exclusion statistics
      def generate_validation_summary(config)
        excluded_services = config.services.select { |_, service_config|
          service_config['exclude_from_automation'] == true
        }

        excluded_by_type = excluded_services.group_by { |_, service_config|
          service_config.dig('exclusion_config', 'type') || 'unspecified'
        }

        summary_data = {
          environments_count: config.environments.length,
          services_count: config.services.length,
          excluded_services_count: excluded_services.length,
          excluded_services_by_type: excluded_by_type.transform_values(&:length),
          directory_stacks_count: config.send(:directory_stacks).length,
          branch_patterns_count: config.branch_patterns.length
        }

        [
          "✅ Configuration validation successful",
          "📋 Summary:",
          "  - environments: #{summary_data[:environments_count]} configured",
          "  - services: #{summary_data[:services_count]} configured (#{summary_data[:excluded_services_count]} excluded)",
          "  - directory stacks: #{summary_data[:directory_stacks_count]} configured",
          "  - branch patterns: #{summary_data[:branch_patterns_count]} configured"
        ].join("\n")
      end
    end
  end
end
