module Entities
  class WorkflowConfigParser
    CONFIG_FIELDS = %w[labels profiles services].freeze
    SERVICE_FIELDS = %w[id roots attributes ignore stacks].freeze
    STACK_FIELDS = %w[id path attributes environments exclude].freeze
    MATRIX_KEYS = %w[service environment stack working_directory].freeze
    LABEL_FIELDS = %w[prefix extra_prefixes].freeze
    REPLACED_FIELDS = { 'stacks' => 'services' }.freeze

    ServiceContext = Struct.new(:id, :position, :roots, :attribute_layer)
    AttributeLayer = Struct.new(:owner, :position, :values)

    def self.parse(config_hash)
      new.parse(config_hash)
    end

    def parse(config_hash)
      validate_map!(config_hash, 'configuration', allowed: CONFIG_FIELDS, replaced: REPLACED_FIELDS)
      labels = config_hash.fetch('labels', {})
      validate_labels!(labels)
      profiles = config_hash.fetch('profiles', {})
      validate_profiles!(profiles)
      validate_array!(config_hash['services'], 'services')
      service_identities = []
      stack_identities = []
      services = config_hash['services'].each_with_index.map do |service, index|
        position = "services[#{index}]"
        validate_service!(service, position)
        invalid!("#{position}.id", "duplicate identity '#{service['id']}'") if service_identities.include?(service['id'])
        service_identities << service['id']
        context = ServiceContext.new(
          service['id'], position, service['roots'].map { |root| normalize_path(root) },
          AttributeLayer.new('service attributes', "#{position}.attributes", service.fetch('attributes', {}))
        )
        service_stacks = service['stacks'].each_with_index.map do |stack, stack_index|
          stack_position = "#{position}.stacks[#{stack_index}]"
          normalized = build_stack(stack, stack_position, context, profiles)
          invalid!("#{stack_position}.id", "duplicate identity '#{stack['id']}'") if stack_identities.include?(stack['id'])
          stack_identities << stack['id']
          normalized
        end
        Service.new(id: service['id'], roots: context.roots, ignore: service.fetch('ignore', []).map { |pattern| normalize_path(pattern) }, stacks: service_stacks)
      end
      WorkflowConfig.new(
        label_prefix: labels.fetch('prefix', DeployLabel::DEFAULT_PREFIX),
        extra_label_prefixes: labels.fetch('extra_prefixes', []),
        services: services
      )
    end

    private

    def validate_labels!(labels)
      validate_map!(labels, 'labels', allowed: LABEL_FIELDS)
      validate_string!(labels['prefix'], 'labels.prefix') if labels.key?('prefix')
      extras = labels.fetch('extra_prefixes', [])
      validate_array!(extras, 'labels.extra_prefixes', allow_empty: true)
      extras.each_with_index { |prefix, index| validate_string!(prefix, "labels.extra_prefixes[#{index}]") }
      # The dispatcher removes every label starting with its prefix, so no prefix may start with another.
      ([labels.fetch('prefix', DeployLabel::DEFAULT_PREFIX)] + extras).combination(2).each do |first, second|
        invalid!('labels', "prefix '#{first}' overlaps '#{second}'") if first.start_with?(second) || second.start_with?(first)
      end
    end

    def validate_profiles!(profiles)
      validate_map!(profiles, 'profiles')
      profiles.each { |name, attributes| validate_attributes!(attributes, "profiles.#{name}", reserve_use: true) }
    end

    def validate_service!(service, position)
      validate_map!(service, position, allowed: SERVICE_FIELDS)
      validate_string!(service['id'], "#{position}.id")
      validate_array!(service['roots'], "#{position}.roots")
      service['roots'].each_with_index do |root, index|
        root_position = "#{position}.roots[#{index}]"
        names = validate_pattern!(root, root_position)
        invalid!(root_position, 'must include {service}') unless names.include?('service')
        invalid!(root_position, '{environment} cannot be used in roots') if names.include?('environment')
      end
      validate_attributes!(service.fetch('attributes', {}), "#{position}.attributes", reserve_use: true)
      ignore = service.fetch('ignore', [])
      validate_array!(ignore, "#{position}.ignore", allow_empty: true)
      ignore.each_with_index do |pattern, index|
        ignore_position = "#{position}.ignore[#{index}]"
        validate_string!(pattern, ignore_position)
        validate_relative!(pattern, ignore_position)
      end
      validate_array!(service['stacks'], "#{position}.stacks")
    end

    def build_stack(stack, position, context, profiles)
      validate_map!(stack, position, allowed: STACK_FIELDS)
      validate_string!(stack['id'], "#{position}.id")
      path_position = "#{position}.path"
      path_names = validate_pattern!(stack['path'], path_position)
      invalid!(path_position, '{service} cannot be used in stack paths') if path_names.include?('service')
      stack_layer = AttributeLayer.new('stack attributes', "#{position}.attributes", stack.fetch('attributes', {}))
      validate_attributes!(stack_layer.values, stack_layer.position, reserve_use: true)
      base_layers = [context.attribute_layer, stack_layer]
      environment_layers = compose_environment_layers(stack, position, base_layers, profiles) if stack.key?('environments')
      common = environment_layers.nil? && !path_names.include?('environment')
      layers = (base_layers + (environment_layers || {}).values.flatten).uniq

      placeholders = validate_stack_placeholders!(context, path_names, path_position, layers, common)
      validate_exclusions!(stack, position, placeholders, common)

      path = normalize_path(stack['path'])
      attributes = merge_layers(base_layers, stack_layer.position)
      environments = environment_layers&.to_h { |name, entry_layers| [name, merge_layers(entry_layers, "#{position}.environments.#{name}")] }
      Stack.new(
        id: stack['id'],
        service_id: context.id,
        path: path,
        paths: context.roots.map { |root| normalize_path("#{root}/#{path}") },
        attributes: attributes,
        environments: environments,
        exclude: stack.fetch('exclude', [])
      )
    end

    def validate_stack_placeholders!(context, path_names, path_position, layers, common)
      attribute_keys = layers.flat_map { |layer| layer.values.keys }
      context.roots.each_with_index.flat_map do |root, index|
        root_position = "#{context.position}.roots[#{index}]"
        names = PatternMatcher.placeholders(root) + path_names
        collision = (names - %w[service environment]).find { |name| attribute_keys.include?(name) }
        if collision
          collision_position = path_names.include?(collision) ? path_position : root_position
          invalid!(collision_position, "placeholder '#{collision}' collides with a matrix or attribute key")
        end
        available = common ? names : names + ['environment']
        layers.each do |layer|
          validate_attribute_templates!(layer.values, layer.position, available, "#{root_position} and #{path_position}")
        end
        names
      end
    end

    def compose_environment_layers(stack, position, base_layers, profiles)
      environments = stack['environments']
      validate_map!(environments, "#{position}.environments")
      invalid!("#{position}.environments", 'must not be empty') if environments.empty?
      environments.to_h do |name, entry|
        environment_position = "#{position}.environments.#{name}"
        validate_segment!(name, environment_position)
        validate_map!(entry, environment_position)
        inline = entry.except('use')
        validate_attributes!(inline, environment_position)
        profile_layers = []
        if entry.key?('use')
          validate_array!(entry['use'], "#{environment_position}.use")
          entry['use'].each_with_index do |profile, index|
            use_position = "#{environment_position}.use[#{index}]"
            validate_string!(profile, use_position)
            invalid!(use_position, "profile '#{profile}' is not defined") unless profiles.key?(profile)
            profile_layers << AttributeLayer.new("profile '#{profile}'", "profiles.#{profile}", profiles[profile])
          end
        end
        [name, base_layers + profile_layers + [AttributeLayer.new('inline attributes', environment_position, inline)]]
      end
    end

    def merge_layers(layers, position)
      owners = {}
      layers.each_with_object({}) do |layer, merged|
        layer.values.each do |key, value|
          invalid!(position, "attribute '#{key}' is defined by both #{owners[key]} and #{layer.owner}") if owners.key?(key)
          owners[key] = layer.owner
          merged[key] = value
        end
      end
    end

    def validate_pattern!(pattern, position)
      validate_string!(pattern, position)
      validate_relative!(pattern, position)
      remaining = pattern.gsub(PatternMatcher::PLACEHOLDER_REGEX, '')
      invalid!(position, 'invalid placeholder syntax') if remaining.include?('{') || remaining.include?('}')
      names = PatternMatcher.placeholders(pattern)
      collision = (names - %w[service environment]).find { |name| MATRIX_KEYS.include?(name) }
      invalid!(position, "placeholder '#{collision}' collides with a matrix or attribute key") if collision
      names
    end

    def validate_relative!(pattern, position)
      invalid!(position, 'must be relative') if pattern.start_with?('/')
      invalid!(position, 'must not contain parent-directory segments') if pattern.split('/').include?('..')
    end

    def normalize_path(pattern)
      pattern.split('/').reject { |part| part.empty? || part == '.' }.join('/')
    end

    def validate_exclusions!(stack, position, placeholders, common)
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
            elsif common
              invalid!(condition_position, 'common targets require a null environment') unless value.nil?
            else
              validate_segment!(value, condition_position)
            end
          else
            validate_segment!(value, condition_position)
            invalid!(condition_position, 'service must not start with a dot') if key == 'service' && Service.hidden_name?(value)
          end
        end
      end
    end

    def validate_attributes!(attributes, position, reserve_use: false)
      validate_map!(attributes, position)
      invalid!("#{position}.use", 'use can only be set in environments') if reserve_use && attributes.key?('use')
      attributes.each_key do |key|
        invalid!("#{position}.#{key}", 'collides with a matrix key') if MATRIX_KEYS.include?(key)
      end
    end

    def validate_attribute_templates!(value, position, available, path_position)
      case value
      when String
        unknown = PatternMatcher.placeholders(value) - available
        invalid!(position, "placeholders #{unknown.join(', ')} cannot be resolved by #{path_position}") unless unknown.empty?
      when Hash
        value.each { |key, nested| validate_attribute_templates!(nested, "#{position}.#{key}", available, path_position) }
      when Array
        value.each_with_index { |nested, index| validate_attribute_templates!(nested, "#{position}[#{index}]", available, path_position) }
      end
    end

    def validate_map!(value, position, allowed: nil, replaced: {})
      invalid!(position, 'must be a map') unless value.is_a?(Hash)
      value.each_key do |key|
        validate_string!(key, "#{position}.keys")
        invalid!("#{position}.#{key}", "unknown field; use #{replaced[key]}") if replaced.key?(key)
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
