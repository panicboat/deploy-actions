module UseCases
  module LabelResolver
    class ListServiceTargets
      def initialize(list_candidates:)
        @list_candidates = list_candidates
      end

      def execute(service:, environments:)
        return Entities::Result.failure(Entities::Service.invalid_name_message(service)) unless Entities::Service.valid_name?(service)

        candidates = @list_candidates.execute(services: [service], environments: environments)
        return candidates if candidates.failure?

        # Building before filtering keeps an unbuildable excluded candidate a failure instead of hiding it.
        Entities::Result.success(candidates.value.map(&:to_listed_target).reject(&:excluded?).map(&:target))
      rescue => error
        Entities::Result.failure("Failed to resolve service targets: #{error.message}")
      end
    end
  end
end
