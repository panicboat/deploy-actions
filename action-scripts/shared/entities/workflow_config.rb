module Entities
  class WorkflowConfig
    STACK_FIELDS = %w[name id paths environments attributes exclude].freeze
    MATRIX_KEYS = %w[service environment stack stack_id working_directory].freeze

    attr_reader :stacks, :environment_names

    def initialize(config_hash)
      validate_map!(config_hash, 'configuration', allowed: ['stacks'])
      validate_array!(config_hash['stacks'], 'stacks')
      identities = []
      @stacks = config_hash['stacks'].each_with_index.map do |stack, index|
        position = "stacks[#{index}]"
        validate_stack!(stack, position)
        identity = stack.fetch('id', stack['name'])
        invalid!("#{position}.id", "duplicate identity '#{identity}'") if identities.include?(identity)
        identities << identity
        normalized = stack.merge(
          'id' => identity,
          'paths' => stack['paths'].map { |pattern| pattern.split('/').reject { |part| part.empty? || part == '.' }.join('/') },
          'exclude' => stack.fetch('exclude', []).map(&:dup)
        )
        if stack.key?('environments')
          normalized['environments'] = stack['environments'].transform_values(&:dup)
        else
          normalized['attributes'] = stack.fetch('attributes', {}).dup
        end
        normalized
      end
      @environment_names = stacks.flat_map { |stack| stack.fetch('environments', {}).keys }.uniq
    end

    def excluded?(stack, values)
      stack['exclude'].any? do |rule|
        rule.all? { |key, expected| values.key?(key) && values[key] == expected }
      end
    end

    private

    def validate_stack!(stack, position)
      validate_map!(stack, position, allowed: STACK_FIELDS)
      validate_string!(stack['name'], "#{position}.name")
      validate_string!(stack['id'], "#{position}.id") if stack.key?('id')
      validate_array!(stack['paths'], "#{position}.paths")
      if stack.key?('environments') && stack.key?('attributes')
        invalid!(position, 'attributes and environments cannot be combined')
      end

      attribute_keys = []
      if stack.key?('environments')
        environments = stack['environments']
        validate_map!(environments, "#{position}.environments")
        invalid!("#{position}.environments", 'must not be empty') if environments.empty?
        environments.each do |name, attributes|
          validate_segment!(name, "#{position}.environments.#{name}")
          validate_attributes!(attributes, "#{position}.environments.#{name}")
          attribute_keys.concat(attributes.keys)
        end
      else
        attributes = stack.fetch('attributes', {})
        validate_attributes!(attributes, "#{position}.attributes")
        attribute_keys.concat(attributes.keys)
      end

      placeholders = []
      stack['paths'].each_with_index do |pattern, index|
        path_position = "#{position}.paths[#{index}]"
        validate_string!(pattern, path_position)
        invalid!(path_position, 'must be repository-relative') if pattern.start_with?('/')
        invalid!(path_position, 'must not contain parent-directory segments') if pattern.split('/').include?('..')
        names = PatternMatcher.placeholders(pattern)
        remaining = pattern.gsub(PatternMatcher::PLACEHOLDER_REGEX, '')
        invalid!(path_position, 'invalid placeholder syntax') if remaining.include?('{') || remaining.include?('}')
        invalid!(path_position, 'must include {service}') unless names.include?('service')
        if !stack.key?('environments') && names.include?('environment')
          invalid!(path_position, '{environment} requires environments')
        end
        custom_names = names - %w[service environment]
        collision = custom_names.find { |name| MATRIX_KEYS.include?(name) || attribute_keys.include?(name) }
        invalid!(path_position, "placeholder '#{collision}' collides with a matrix or attribute key") if collision
        placeholders.concat(names)
      end

      validate_exclusions!(stack, position, placeholders)
    end

    def validate_exclusions!(stack, position, placeholders)
      rules = stack.fetch('exclude', [])
      validate_array!(rules, "#{position}.exclude", allow_empty: true)
      allowed = (%w[service environment] + placeholders).uniq
      rules.each_with_index do |rule, index|
        rule_position = "#{position}.exclude[#{index}]"
        validate_map!(rule, rule_position, allowed: allowed)
        invalid!(rule_position, 'must contain at least one condition') if rule.empty?
        rule.each do |key, value|
          condition_position = "#{rule_position}.#{key}"
          if key == 'environment'
            if stack.key?('environments')
              validate_segment!(value, condition_position)
              unless stack['environments'].key?(value)
                invalid!(condition_position, "environment '#{value}' is not declared in this stack")
              end
            elsif !value.nil?
              invalid!(condition_position, 'common targets require a null environment')
            end
          else
            validate_segment!(value, condition_position)
            invalid!(condition_position, 'service must not start with a dot') if key == 'service' && value.start_with?('.')
          end
        end
      end
    end

    def validate_attributes!(attributes, position)
      validate_map!(attributes, position)
      attributes.each_key do |key|
        invalid!("#{position}.#{key}", 'collides with a matrix key') if MATRIX_KEYS.include?(key)
      end
    end

    def validate_map!(value, position, allowed: nil)
      invalid!(position, 'must be a map') unless value.is_a?(Hash)
      value.each_key do |key|
        validate_string!(key, "#{position}.keys")
        invalid!("#{position}.#{key}", 'unknown field') if allowed && !allowed.include?(key)
      end
    end

    def validate_array!(value, position, allow_empty: false)
      invalid!(position, 'must be an array') unless value.is_a?(Array)
      invalid!(position, 'must not be empty') if !allow_empty && value.empty?
    end

    def validate_string!(value, position)
      invalid!(position, 'must be a non-empty string') unless value.is_a?(String) && !value.empty?
    end

    def validate_segment!(value, position)
      validate_string!(value, position)
      invalid!(position, 'must be a single path segment') if value.include?('/') || %w[. ..].include?(value)
    end

    def invalid!(position, reason)
      raise ArgumentError, "Configuration validation failed: #{position}: #{reason}"
    end
  end
end
