# Configuration client for loading and parsing YAML configuration files
# Handles workflow configuration loading with validation

require 'yaml'

module Infrastructure
  class ConfigClient
    def initialize(config_path: nil)
      @config_path = config_path || ENV['WORKFLOW_CONFIG_PATH'] || 'shared/workflow-config.yaml'
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

    private

    # Validate the configuration structure
    def validate_config!(config_data)
      raise "Configuration must be a Hash" unless config_data.is_a?(Hash)

      # Validate required sections
      required_sections = %w[environments directory_conventions defaults]
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

      # Validate directory_conventions section
      conventions = config_data['directory_conventions']
      raise "directory_conventions must be a Hash" unless conventions.is_a?(Hash)
      raise "directory_conventions must have 'terragrunt' key" unless conventions['terragrunt']

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
