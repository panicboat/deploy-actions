module UseCases
  module LabelResolver
    class ListServiceTargets
      def initialize(list_candidates:)
        @list_candidates = list_candidates
      end

      def execute(service:, environments:)
        unless service.match?(Entities::DeployLabel::SERVICE_PATTERN)
          return Entities::Result.failure("Invalid service name: #{service.inspect} (use all or a name matching [a-zA-Z0-9_-]+)")
        end

        candidates = @list_candidates.execute(services: service == 'all' ? nil : [service], environments: environments)
        return candidates if candidates.failure?

        listed = candidates.value.map(&:to_listed_target)
        Entities::Result.success(Entities::ServiceTargets.new(targets: listed.reject(&:excluded?).map(&:target), candidates: listed))
      rescue => error
        Entities::Result.failure("Failed to resolve service targets: #{error.message}")
      end
    end
  end
end
