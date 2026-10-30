module Entities
  class TargetCandidates
    RESERVED_CAPTURES = %w[service environment].freeze

    def initialize
      @candidates = {}
    end

    def add(stack:, service:, environment:, working_directory:, captures:)
      custom = captures.reject { |key, _| RESERVED_CAPTURES.include?(key) }
      identity = [service, stack.id, environment, working_directory]
      existing = @candidates[identity]
      if existing && existing.captures != custom
        raise "Conflicting captures for stack '#{stack.id}' at '#{working_directory}'"
      end
      @candidates[identity] = TargetCandidate.new(
        stack: stack, service: service, environment: environment,
        working_directory: working_directory, captures: custom
      )
    end

    def to_a
      @candidates.values
    end
  end
end
