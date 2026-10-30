module UseCases
  module Shared
    class ResolveEnvironments
      def initialize(directory_scanner:)
        @directory_scanner = directory_scanner
      end

      def execute(config:, requested:)
        available = (config.declared_environment_names + discovered_environment_names(config)).uniq
        environments = requested.nil? || requested.empty? ? available : requested.uniq
        unknown = environments - available
        return Entities::Result.failure("Target environments not found in configuration: #{unknown.join(', ')}") unless unknown.empty?

        Entities::Result.success(environments)
      end

      private

      def discovered_environment_names(config)
        config.stacks.select(&:discovers_environments?).flat_map do |stack|
          stack.paths.flat_map do |pattern|
            @directory_scanner.resolve_directories(pattern: pattern, values: {}).filter_map do |match|
              captures = match.fetch(:captures)
              captures.fetch('environment') unless Entities::Service.hidden_name?(captures.fetch('service'))
            end
          end
        end
      end
    end
  end
end
