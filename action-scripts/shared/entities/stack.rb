module Entities
  Stack = Data.define(:id, :path, :paths, :attributes, :environments, :exclude) do
    def initialize(**fields)
      super(**Ractor.make_shareable(fields, copy: true))
    end

    def common?
      environments.nil? && !PatternMatcher.placeholders(path).include?('environment')
    end

    def declares_environments?
      !environments.nil?
    end

    def discovers_environments?
      !declares_environments? && !common?
    end

    def declared_environment_names
      declares_environments? ? environments.keys : []
    end

    def target_environments(candidates)
      if declares_environments?
        candidates & environments.keys
      elsif common?
        [nil]
      else
        candidates
      end
    end

    def excluded?(values)
      exclude.any? do |rule|
        rule.all? { |key, expected| values.key?(key) && values[key] == expected }
      end
    end

    def target_attributes(environment)
      declares_environments? ? environments.fetch(environment) : attributes
    end
  end
end
