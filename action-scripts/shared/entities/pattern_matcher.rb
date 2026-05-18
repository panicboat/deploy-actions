# Value object encoding workflow-config placeholder grammar.
# Used by label-dispatcher, label-resolver, and config-manager to share
# a single source of truth for "{name}" handling.

module Entities
  class PatternMatcher
    # Matches placeholders like {service}, {team}, {env_a1}.
    # Uppercase and hyphenated names ({Team}, {my-var}) are treated as literals.
    PLACEHOLDER_REGEX = /\{([a-z_][a-z0-9_]*)\}/

    # Returns placeholder names in left-to-right order, including duplicates.
    def self.placeholders(pattern)
      return [] if pattern.nil?
      pattern.scan(PLACEHOLDER_REGEX).map(&:first)
    end

    # Substitutes {name} with values[name]. Values are looked up by string key.
    # Raises UnresolvedPlaceholderError if a placeholder has no value.
    # Raises ArgumentError if a substituted value contains "/".
    def self.expand(pattern, values)
      return pattern if pattern.nil?

      pattern.gsub(PLACEHOLDER_REGEX) do
        name = Regexp.last_match(1)
        unless values.key?(name)
          raise UnresolvedPlaceholderError, "no value for '{#{name}}' in pattern: #{pattern}"
        end
        value = values[name].to_s
        if value.include?('/')
          raise ArgumentError, "value for '{#{name}}' must not contain '/': #{value}"
        end
        value
      end
    end
  end

  class UnresolvedPlaceholderError < StandardError; end
end
