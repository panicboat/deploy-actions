module UseCases
  module ConfigManagement
    class TestService
      def initialize(list_candidates:)
        @list_candidates = list_candidates
      end

      def execute(service_name:, environment:)
        return Entities::Result.failure(Entities::Service.invalid_name_message(service_name)) unless Entities::Service.valid_name?(service_name)

        candidates = @list_candidates.execute(services: [service_name], environments: environment && [environment])
        return candidates if candidates.failure?

        Entities::Result.success(candidates.value.map(&:to_listed_target))
      rescue => error
        Entities::Result.failure("Failed to test service configuration: #{error.message}")
      end
    end
  end
end
