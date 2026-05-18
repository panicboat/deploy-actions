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

    # Returns a Hash mapping placeholder names to captured values, or nil if
    # the path does not match the pattern in full. Captures cannot span "/".
    def self.extract(pattern, path)
      return nil if pattern.nil? || path.nil?
      regex = Regexp.new("\\A#{compile_regex_body(pattern)}\\z")
      match_to_hash(regex.match(path), pattern)
    end

    # Like extract, but only requires the pattern to match the prefix of path.
    # Path may carry additional "/"-separated segments after the pattern.
    def self.extract_prefix(pattern, path)
      return nil if pattern.nil? || path.nil?
      regex = Regexp.new("\\A#{compile_regex_body(pattern)}(?:/.*)?\\z")
      match_to_hash(regex.match(path), pattern)
    end

    # Build a regex body where each {name} becomes a named capture (or
    # backreference for duplicates) and every other character is escaped.
    def self.compile_regex_body(pattern)
      seen = []
      buffer = +''
      rest = pattern.dup

      loop do
        break if rest.empty?

        if (m = rest.match(/\A#{PLACEHOLDER_REGEX.source}/))
          name = m[1]
          if seen.include?(name)
            buffer << "\\k<#{name}>"
          else
            buffer << "(?<#{name}>[^/]+)"
            seen << name
          end
          rest = rest[m[0].length..]
        else
          buffer << Regexp.escape(rest[0])
          rest = rest[1..]
        end
      end

      buffer
    end
    private_class_method :compile_regex_body

    def self.match_to_hash(match_data, pattern)
      return nil unless match_data
      placeholders(pattern).uniq.each_with_object({}) do |name, hash|
        hash[name] = match_data[name]
      end
    end
    private_class_method :match_to_hash
  end

  class UnresolvedPlaceholderError < StandardError; end
end
