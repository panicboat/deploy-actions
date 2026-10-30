module Entities
  TargetCandidate = Data.define(:stack, :service, :environment, :working_directory, :captures) do
    def exclusion_values
      captures.merge('service' => service, 'environment' => environment)
    end

    def excluded?
      stack.excluded?(exclusion_values)
    end

    def to_deployment_target
      DeploymentTarget.new(
        service: service, environment: environment, stack: stack.id,
        working_directory: working_directory, captures: captures, attributes: stack.target_attributes(environment)
      )
    end
  end
end
