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
  end

  class UnresolvedPlaceholderError < StandardError; end
end
