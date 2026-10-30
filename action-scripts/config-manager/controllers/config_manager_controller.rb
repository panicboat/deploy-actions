# Controller for configuration management functionality

module Interfaces
  module Controllers
    class ConfigManagerController
      def initialize(validate_config:, test_service:, presenter:)
        @validate_config = validate_config
        @test_service = test_service
        @presenter = presenter
      end

      def validate
        result = @validate_config.execute
        if result.success?
          @presenter.present_config_validation_result(valid: true, summary: result.value.summary)
        else
          @presenter.present_config_validation_result(valid: false, errors: [result.error_message])
        end
        result
      end

      def test_service(service_name:, environment:)
        result = @test_service.call.execute(service_name: service_name, environment: environment)
        return failure(result) if result.failure?

        @presenter.present_service_test_result(service_name: service_name, candidates: result.value)
        result
      end

      private

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end
    end
  end
end
