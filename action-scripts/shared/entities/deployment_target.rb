# Deployment target entity representing a specific deployment configuration
# Contains all necessary information for a deployment matrix item

module Entities
  class DeploymentTarget
    FIXED_RESERVED_KEYS = %w[service environment stack working_directory stack_convention_root].freeze

    attr_reader :service, :environment, :stack,
                :working_directory, :stack_convention_root, :attributes, :captures

    def initialize(service:, stack:, working_directory:,
                   environment: nil, stack_convention_root: nil,
                   attributes: {}, captures: {})
      raise ArgumentError, "service is required"           if service.nil?           || service.empty?
      raise ArgumentError, "stack is required"             if stack.nil?             || stack.empty?
      raise ArgumentError, "working_directory is required" if working_directory.nil? || working_directory.empty?

      attr_keys = attributes.keys.map(&:to_s)
      captures.each_key do |raw_key|
        key = raw_key.to_s
        if FIXED_RESERVED_KEYS.include?(key)
          raise ArgumentError, "captures key '#{key}' collides with a reserved DeploymentTarget field"
        end
        if attr_keys.include?(key)
          raise ArgumentError, "captures key '#{key}' collides with an attributes key"
        end
      end

      @service               = service
      @environment           = environment
      @stack                 = stack
      @working_directory     = working_directory
      @stack_convention_root = stack_convention_root
      @attributes            = attributes.freeze
      @captures              = captures.freeze
    end

    def to_matrix_item
      {
        service: service,
        environment: environment,
        stack: stack,
        working_directory: working_directory,
        stack_convention_root: stack_convention_root,
      }.merge(attributes.transform_keys(&:to_sym))
       .merge(captures.transform_keys(&:to_sym))
    end

    def ==(other)
      return false unless other.is_a?(DeploymentTarget)
      [service, environment, stack, working_directory] ==
        [other.service, other.environment, other.stack, other.working_directory]
    end

    def hash
      [service, environment, stack, working_directory].hash
    end

    alias eql? ==
  end
end
