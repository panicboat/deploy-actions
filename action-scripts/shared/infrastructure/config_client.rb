# Configuration client for loading and parsing YAML configuration files
# Handles workflow configuration loading with validation

require 'yaml'

module Infrastructure
  class ConfigClient
    def initialize(config_path: nil)
      @config_path = config_path || ENV['WORKFLOW_CONFIG_PATH'] || 'workflow-config.yaml'
      @config_cache = nil
    end

    # Load workflow configuration from YAML file
    def load_workflow_config
      return @config_cache if @config_cache

      unless File.exist?(@config_path)
        raise "Configuration file not found: #{@config_path}"
      end

      begin
        content = File.read(@config_path)
        config_data = YAML.safe_load(content)
        validate_config!(config_data)
        @config_cache = Entities::WorkflowConfig.new(config_data)
      rescue Errno::EACCES
        raise "Permission denied accessing configuration file: #{@config_path}"
      rescue Psych::SyntaxError => e
        raise "YAML parsing error at line #{e.line}: #{e.message}"
      rescue => error
        raise "Failed to load configuration from #{@config_path}: #{error.message}"
      end
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

    # Clear configuration cache (useful for testing)
    def clear_cache
      @config_cache = nil
    end

    private

    # Get the configuration file path
    def config_file_path
      @config_path
    end

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
      ].join("\n")
    end

    # Validate the configuration structure
    def validate_config!(config_data)
      raise "Configuration must be a Hash" unless config_data.is_a?(Hash)

      # Validate required sections
      required_sections = %w[environments directory_conventions]
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
      raise "directory_conventions must be an Array" unless conventions.is_a?(Array)

      conventions.each_with_index do |convention, conv_index|
        raise "directory_conventions[#{conv_index}] must have 'root' key" unless convention.key?('root')
        raise "directory_conventions[#{conv_index}] must have 'stacks' key" unless convention['stacks']

        stacks = convention['stacks']
        raise "directory_conventions[#{conv_index}].stacks must be an Array" unless stacks.is_a?(Array)

        stacks.each_with_index do |stack, stack_index|
          raise "directory_conventions[#{conv_index}].stacks[#{stack_index}] must have 'name' key" unless stack['name']
          raise "directory_conventions[#{conv_index}].stacks[#{stack_index}] must have 'directory' key" unless stack['directory']
        end
      end


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
