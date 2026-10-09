require 'yaml'

module Infrastructure
  class ConfigClient
    def initialize(config_path: nil)
      @config_path = config_path || ENV['WORKFLOW_CONFIG_PATH'] || 'workflow-config.yaml'
      @config_cache = nil
    end

    def load_workflow_config
      return @config_cache if @config_cache

      @config_cache = Entities::WorkflowConfig.new(YAML.safe_load(File.read(@config_path)))
    rescue Errno::ENOENT
      raise "Configuration file not found: #{@config_path}"
    rescue Errno::EACCES
      raise "Permission denied accessing configuration file: #{@config_path}"
    rescue Psych::SyntaxError => error
      raise "YAML parsing error at line #{error.line}: #{error.message}"
    rescue StandardError => error
      raise "Failed to load configuration from #{@config_path}: #{error.message}"
    end

    def clear_cache
      @config_cache = nil
    end
  end
end
