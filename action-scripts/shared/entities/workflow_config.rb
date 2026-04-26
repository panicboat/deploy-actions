# Workflow configuration entity representing the parsed YAML configuration
# Provides access to environments, services, and directory conventions

module Entities
  class WorkflowConfig
    attr_reader :raw_config

    def initialize(config_hash)
      @raw_config = config_hash
      validate!
    end

    # Get environment configuration (no defaults merging)
    def environment_config(env_name)
      environments[env_name]
    end

    # Get directory conventions for a service and stack with hierarchical structure
    def stack_conventions_for(service_name, stack = 'terragrunt')
      service_config = services[service_name]
      if service_config && service_config['stack_conventions']
        # If service has stack_conventions, only return service-specific pattern if it exists
        if service_config['stack_conventions'][stack]
          return [service_config['stack_conventions'][stack]]
        else
          # Service has stack_conventions but not for this stack
          return []
        end
      end

      # Use hierarchical structure: root + stack directory
      patterns = []
      stack_conventions_config.each do |convention|
        root_pattern = convention['root']
        stack_config = convention['stacks']&.find { |s| s['name'] == stack }
        next unless stack_config

        # Handle empty root pattern
        if root_pattern.nil? || root_pattern.empty?
          patterns << stack_config['directory']
        else
          patterns << "#{root_pattern}/#{stack_config['directory']}"
        end
      end
      patterns
    end

    # Get directory convention for a service and stack (returns first match)
    def stack_convention_for(service_name, stack = 'terragrunt')
      conventions = stack_conventions_for(service_name, stack)
      conventions.first
    end

    # Get all environments as a hash
    def environments
      @environments ||= (raw_config['environments'] || []).each_with_object({}) do |env, hash|
        hash[env['environment']] = env
      end
    end

    # Get all services as a hash
    def services
      @services ||= (raw_config['services'] || []).each_with_object({}) do |service, hash|
        hash[service['name']] = service
      end
    end


    # Check if safety check is enabled
    def safety_check_enabled?(check_name)
      false
    end

    # Get list of services excluded from automation
    def excluded_services
      @excluded_services ||= services.select { |_, service|
        service['exclude_from_automation'] == true
      }.keys
    end


    # Get directory conventions (for backward compatibility)
    def stack_conventions
      stack_conventions_config
    end

    # Get directory conventions root patterns
    def stack_convention_roots
      stack_conventions_config.map { |conv| conv['root'] }.compact
    end

    # Get directory conventions root pattern (returns first pattern)
    def stack_convention_root
      stack_convention_roots.first
    end

    # Validate configuration structure
    def validate!
      errors = []

      errors << "Missing required section: environments" unless raw_config['environments']
      errors << "Missing required section: stack_conventions" unless raw_config['stack_conventions']

      if raw_config['environments']
        raw_config['environments'].each_with_index do |env, index|
          unless env['environment']
            errors << "Environment at index #{index} missing required field: environment"
          end
        end
      end

      if raw_config['stack_conventions']
        unless raw_config['stack_conventions'].is_a?(Array)
          errors << "stack_conventions must be an array"
        else
          raw_config['stack_conventions'].each_with_index do |conv, index|
            unless conv['root']
              errors << "stack_conventions[#{index}] missing required field: root"
            end
            unless conv['stacks']
              errors << "stack_conventions[#{index}] missing required field: stacks"
            end
          end
        end
      end

      raise StandardError, "Configuration validation failed: #{errors.join(', ')}" unless errors.empty?
    end

    # Get directory conventions configuration
    def stack_conventions_config
      @stack_conventions_config ||= raw_config['stack_conventions'] || []
    end

    # Get all possible directory patterns for service discovery
    def all_directory_patterns
      patterns = []
      
      stack_conventions_config.each do |convention|
        root_pattern = convention['root']
        stacks = convention['stacks'] || []
        
        # Add root pattern for detecting any change within service directory
        if root_pattern && root_pattern.include?('{service}')
          patterns << root_pattern
        end
        
        stacks.each do |stack_config|
          stack_directory = stack_config['directory']
          next unless stack_directory
          
          # Build full pattern using root + stack directory
          full_pattern = if root_pattern.nil? || root_pattern.empty?
                          stack_directory
                        else
                          "#{root_pattern}/#{stack_directory}"
                        end
          
          # Only include patterns that contain {service}
          patterns << full_pattern if full_pattern.include?('{service}')
        end
      end
      
      patterns.uniq
    end

    private

    # Get directory stacks configuration
    def directory_stacks
      @directory_stacks ||= stack_conventions_config.first&.fetch('stacks', []) || []
    end
  end
end
