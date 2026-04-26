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
          validation_errors.concat(validate_stack_conventions(config))
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

        environments.each do |env_name, env_config|
          errors.concat(validate_environment_config(env_name, env_config, config))
        end

        errors
      end

      # Validate individual environment configuration
      def validate_environment_config(env_name, env_config, config)
        errors = []

        # Validate stacks structure if present
        if env_config.key?('stacks')
          stacks = env_config['stacks']
          unless stacks.is_a?(Hash)
            errors << "Environment '#{env_name}' 'stacks' must be a Hash"
            return errors
          end
        end

        # Check required_attributes for each stack declared in stack_conventions
        config.stack_conventions_config.each do |convention|
          (convention['stacks'] || []).each do |stack_def|
            stack_name = stack_def['name']
            required = stack_def['required_attributes'] || []
            next if required.empty?

            # Skip when the environment does not declare this stack — it opts out of the stack
            stack_attrs = env_config.dig('stacks', stack_name)
            next if stack_attrs.nil?

            required.each do |attr|
              unless stack_attrs.key?(attr)
                errors << "Environment '#{env_name}' missing required attribute for stack '#{stack_name}': #{attr}"
              end
            end
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

          if service_config['stack_conventions']
            service_config['stack_conventions'].each do |stack, pattern|
              unless pattern.include?('{service}')
                errors << "Service '#{service_name}' directory convention for '#{stack}' must include {service} placeholder"
              end
            end
          end
        end

        errors
      end

      # Validate directory conventions
      def validate_stack_conventions(config)
        errors = []
        conventions = config.stack_conventions

        if conventions.empty?
          errors << "No directory conventions defined"
          return errors
        end

        # Validate each directory convention
        conventions.each_with_index do |convention, conv_index|
          unless convention.is_a?(Hash)
            errors << "Directory convention at index #{conv_index} must be a Hash"
            next
          end

          # Validate root pattern (can be empty string)
          unless convention.key?('root')
            errors << "Directory convention at index #{conv_index} missing required 'root' field"
          end

          # Only validate {service} placeholder if root is not empty
          if convention['root'] && !convention['root'].empty? && !convention['root'].include?('{service}')
            errors << "Directory convention at index #{conv_index} root must include {service} placeholder"
          end

          # Validate stacks
          stacks = convention['stacks']
          unless stacks.is_a?(Array)
            errors << "Directory convention at index #{conv_index} 'stacks' must be an Array"
            next
          end

          if stacks.empty?
            errors << "Directory convention at index #{conv_index} 'stacks' cannot be empty"
            next
          end

          # Validate each stack
          stacks.each_with_index do |stack, index|
            unless stack['name']
              errors << "Stack at index #{index} in convention #{conv_index} missing required 'name' field"
            end

            unless stack['directory']
              errors << "Stack at index #{index} in convention #{conv_index} missing required 'directory' field"
            end

            # {environment} placeholder is now optional to support environment-agnostic stacks
            # (e.g., Docker builds that are environment-independent)
            # if stack['directory'] && !stack['directory'].include?('{environment}')
            #   errors << "Stack '#{stack['name']}' in convention #{conv_index} directory must include {environment} placeholder"
            # end
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

          unless service_config['stack_conventions']
            puts "INFO: Service '#{service_name}' is excluded and has no stack_conventions defined"
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

        # Count total stacks across all conventions
        total_stacks = config.stack_conventions_config.sum { |conv| conv['stacks']&.length || 0 }

        summary_data = {
          environments_count: config.environments.length,
          services_count: config.services.length,
          excluded_services_count: excluded_services.length,
          excluded_services_by_type: excluded_by_type.transform_values(&:length),
          directory_stacks_count: total_stacks,
        }

        [
          "✅ Configuration validation successful",
          "📋 Summary:",
          "  - environments: #{summary_data[:environments_count]} configured",
          "  - services: #{summary_data[:services_count]} configured (#{summary_data[:excluded_services_count]} excluded)",
          "  - directory stacks: #{summary_data[:directory_stacks_count]} configured",
        ].join("\n")
      end
    end
  end
end
