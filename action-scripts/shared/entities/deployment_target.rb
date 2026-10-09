module Entities
  class DeploymentTarget
    FIXED_RESERVED_KEYS = %w[service environment stack stack_id working_directory].freeze

    attr_reader :service, :environment, :stack, :stack_id, :working_directory, :attributes, :captures

    def initialize(service:, stack:, stack_id:, working_directory:, environment: nil, attributes: {}, captures: {})
      { service: service, stack: stack, stack_id: stack_id, working_directory: working_directory }.each do |key, value|
        raise ArgumentError, "#{key} is required" unless value.is_a?(String) && !value.empty?
      end
      attribute_keys = attributes.keys.map(&:to_s)
      captures.each_key do |raw_key|
        key = raw_key.to_s
        raise ArgumentError, "captures key '#{key}' collides with a reserved DeploymentTarget field" if FIXED_RESERVED_KEYS.include?(key)
        raise ArgumentError, "captures key '#{key}' collides with an attributes key" if attribute_keys.include?(key)
      end

      @service = service
      @environment = environment
      @stack = stack
      @stack_id = stack_id
      @working_directory = working_directory
      values = captures.transform_keys(&:to_s).merge('service' => service)
      values['environment'] = environment unless environment.nil?
      @attributes = expand_attributes(attributes, values).freeze
      @captures = captures.dup.freeze
    end

    def to_matrix_item
      { service: service, environment: environment, stack: stack, stack_id: stack_id, working_directory: working_directory }
        .merge(attributes.transform_keys(&:to_sym)).merge(captures.transform_keys(&:to_sym))
    end

    def ==(other)
      other.is_a?(DeploymentTarget) &&
        [service, stack_id, environment, working_directory] == [other.service, other.stack_id, other.environment, other.working_directory]
    end

    def hash
      [service, stack_id, environment, working_directory].hash
    end

    alias eql? ==

    private

    def expand_attributes(value, values)
      case value
      when String
        PatternMatcher.expand(value, values)
      when Hash
        value.transform_values { |nested| expand_attributes(nested, values) }
      when Array
        value.map { |nested| expand_attributes(nested, values) }
      else
        value
      end
    end
  end
end
