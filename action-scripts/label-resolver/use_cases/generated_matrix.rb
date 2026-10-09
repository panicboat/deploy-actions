module UseCases
  module LabelResolver
    class GenerateMatrix
      def initialize(config_client:, file_client:)
        @config_client = config_client
        @file_client = file_client
      end

      def execute(deploy_labels:, target_environments:)
        config = @config_client.load_workflow_config
        environments = target_environments.nil? || target_environments.empty? ? config.environment_names : target_environments.uniq
        unknown = environments - config.environment_names
        return Entities::Result.failure(error_message: "Target environments not found in configuration: #{unknown.join(', ')}") unless unknown.empty?

        labels = deploy_labels.select(&:valid?)
        services = labels.any?(&:deploy_all?) ? [nil] : labels.map(&:service).uniq
        candidates = {}
        config.stacks.each do |stack|
          selected = stack.key?('environments') ? environments & stack['environments'].keys : [nil]
          selected.each do |environment|
            services.each do |service|
              values = { 'environment' => environment }
              values['service'] = service if service
              stack['paths'].each do |pattern|
                @file_client.resolve_directories(pattern: pattern, values: values).each do |match|
                  captures = match.fetch(:captures)
                  name = captures.fetch('service')
                  next if name.start_with?('.')
                  directory = match.fetch(:working_directory)
                  custom = captures.reject { |key, _| %w[service environment].include?(key) }
                  identity = [name, stack['id'], environment, directory]
                  if candidates.key?(identity) && candidates[identity][:captures] != custom
                    raise "Conflicting captures for stack '#{stack['id']}' at '#{directory}'"
                  end
                  candidates[identity] = { stack: stack, environment: environment, service: name, working_directory: directory, captures: custom }
                end
              end
            end
          end
        end

        targets = candidates.values.filter_map do |candidate|
          stack = candidate.fetch(:stack)
          environment = candidate.fetch(:environment)
          values = candidate.fetch(:captures).merge('service' => candidate.fetch(:service), 'environment' => environment)
          next if config.excluded?(stack, values)
          attributes = stack.key?('environments') ? stack['environments'].fetch(environment) : stack['attributes']
          Entities::DeploymentTarget.new(
            service: candidate.fetch(:service), environment: environment, stack: stack['name'], stack_id: stack['id'],
            working_directory: candidate.fetch(:working_directory), captures: candidate.fetch(:captures), attributes: attributes
          )
        end
        Entities::Result.success(deployment_targets: targets, has_deployments: !targets.empty?, total_targets: targets.length)
      rescue => error
        Entities::Result.failure(error_message: "Failed to generate deployment matrix: #{error.message}")
      end
    end
  end
end
