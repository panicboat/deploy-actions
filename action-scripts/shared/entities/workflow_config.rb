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

    # Get directory convention for a service and stack with hierarchical structure
    def directory_convention_for(service_name, stack = 'terragrunt')
      service_config = services[service_name]
      if service_config && service_config['directory_conventions'] && service_config['directory_conventions'][stack]
        return service_config['directory_conventions'][stack]
      end

      # Use hierarchical structure: root + stack directory
      root_pattern = directory_conventions_config['root']
      stack_config = directory_stacks.find { |s| s['name'] == stack }

      return nil unless stack_config

      # Handle empty root pattern
      if root_pattern.nil? || root_pattern.empty?
        stack_config['directory']
      else
        "#{root_pattern}/#{stack_config['directory']}"
      end
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

    # Map branch name to environment
    def branch_to_environment(branch_name)
      return nil unless branch_name
      branch_patterns[branch_name]
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

    # Get branch patterns for environment mapping
    def branch_patterns
      @branch_patterns ||= raw_config['branch_patterns'] || {}
    end

    # Get directory conventions (for backward compatibility)
    def directory_conventions
      directory_conventions_config
    end

    # Get directory conventions root pattern
    def directory_conventions_root
      directory_conventions_config['root']
    end

    # Validate configuration structure
    def validate!
      errors = []

      errors << "Missing required section: environments" unless raw_config['environments']
      errors << "Missing required section: directory_conventions" unless raw_config['directory_conventions']
      errors << "Missing required section: branch_patterns" unless raw_config['branch_patterns']

      if raw_config['environments']
        raw_config['environments'].each_with_index do |env, index|
          unless env['environment']
            errors << "Environment at index #{index} missing required field: environment"
          end
        end
      end

      if raw_config['directory_conventions']
        unless raw_config['directory_conventions']['root']
          errors << "directory_conventions missing required field: root"
        end
        unless raw_config['directory_conventions']['stacks']
          errors << "directory_conventions missing required field: stacks"
        end
      end

      raise StandardError, "Configuration validation failed: #{errors.join(', ')}" unless errors.empty?
    end

    private

    # Get directory conventions configuration
    def directory_conventions_config
      @directory_conventions_config ||= raw_config['directory_conventions'] || {}
    end

    # Get directory stacks configuration
    def directory_stacks
      @directory_stacks ||= directory_conventions_config['stacks'] || []
    end
  end
end
