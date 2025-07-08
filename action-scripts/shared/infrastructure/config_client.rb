# Configuration client for loading and parsing YAML configuration files
# Handles workflow configuration loading with validation

require 'yaml'

module Infrastructure
  class ConfigClient
    def initialize(config_path: nil)
      @config_path = config_path || ENV['WORKFLOW_CONFIG_PATH'] || 'workflow-config.yaml'
    end

    # Load workflow configuration from YAML file
    def load_workflow_config
      unless File.exist?(@config_path)
        raise "Configuration file not found: #{@config_path}"
      end

      config_data = YAML.load_file(@config_path)
      validate_config!(config_data)
      Entities::WorkflowConfig.new(config_data)
    rescue => error
      raise "Failed to load configuration from #{@config_path}: #{error.message}"
    end

    # Validate configuration file and return result
    def validate_config_file
      begin
        config = load_workflow_config
        validation_summary = build_validation_summary(config)

        Entities::Result.success(
          config: config,
          validation_summary: validation_summary
        )
      rescue => error
        if error.message.include?("Configuration validation failed:")
          validation_errors = error.message.sub("Configuration validation failed: ", "").split(", ")
          Entities::Result.failure(
            error_message: error.message,
            validation_errors: validation_errors
          )
        else
          Entities::Result.failure(error_message: error.message)
        end
      end
    end

    private

    # Build validation summary for successful validation
    def build_validation_summary(config)
      env_count = config.environments.length
      service_count = config.services.length
      excluded_count = config.excluded_services.length
      stack_count = config.send(:directory_stacks).length

      [
        "✅ Configuration validation successful",
        "📋 Summary:",
        "  - environments: #{env_count} configured",
        "  - services: #{service_count} configured (#{excluded_count} excluded)",
        "  - directory stacks: #{stack_count} configured",
        "  - branch patterns: #{config.branch_patterns.keys.join(', ')}"
      ].join("\n")
    end

    # Validate the configuration structure
    def validate_config!(config_data)
      raise "Configuration must be a Hash" unless config_data.is_a?(Hash)

      # Validate required sections
      required_sections = %w[environments directory_conventions branch_patterns]
      missing_sections = required_sections - config_data.keys
      if missing_sections.any?
        raise "Missing required configuration sections: #{missing_sections.join(', ')}"
      end

      # Validate environments section
      environments = config_data['environments']
      raise "environments must be an Array" unless environments.is_a?(Array)

      environments.each_with_index do |env, index|
        raise "Environment #{index} must have 'environment' key" unless env['environment']
        raise "Environment #{index} must have 'aws_region' key" unless env['aws_region']
      end

      # Validate new directory_conventions structure
      conventions = config_data['directory_conventions']
      raise "directory_conventions must be a Hash" unless conventions.is_a?(Hash)
      raise "directory_conventions must have 'root' key" unless conventions['root']
      raise "directory_conventions must have 'stacks' key" unless conventions['stacks']

      stacks = conventions['stacks']
      raise "directory_conventions.stacks must be an Array" unless stacks.is_a?(Array)

      stacks.each_with_index do |stack, index|
        raise "Stack #{index} must have 'name' key" unless stack['name']
        raise "Stack #{index} must have 'directory' key" unless stack['directory']
      end

      # Validate branch_patterns section
      branch_patterns = config_data['branch_patterns']
      raise "branch_patterns must be a Hash" unless branch_patterns.is_a?(Hash)

      # Validate services section if present
      if config_data['services']
        services = config_data['services']
        raise "services must be an Array" unless services.is_a?(Array)

        services.each_with_index do |service, index|
          raise "Service #{index} must have 'name' key" unless service['name']
        end
      end
    end
  end
end
