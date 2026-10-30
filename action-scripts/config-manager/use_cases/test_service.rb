module UseCases
  module ConfigManagement
    class TestService
      def initialize(list_candidates:)
        @list_candidates = list_candidates
      end

      def execute(service_name:, environment:)
        @list_candidates.execute(services: [service_name], environments: environment && [environment])
      rescue => error
        Entities::Result.failure("Failed to test service configuration: #{error.message}")
      end
    end
  end
end
