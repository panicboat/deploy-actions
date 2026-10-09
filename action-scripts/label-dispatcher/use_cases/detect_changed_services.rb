module UseCases
  module LabelManagement
    class DetectChangedServices
      def initialize(file_client:, config_client:)
        @file_client = file_client
        @config_client = config_client
      end

      def execute(base_ref: nil, head_ref: nil)
        config = @config_client.load_workflow_config
        changed_files = @file_client.get_changed_files(base_ref: base_ref, head_ref: head_ref)
        candidates = {}
        config.stacks.each do |stack|
          stack['paths'].each do |pattern|
            changed_files.each do |file|
              captures = Entities::PatternMatcher.extract_prefix(pattern, file)
              next unless captures
              service = captures.fetch('service')
              next if service.start_with?('.')
              environments = if stack.key?('environments')
                stack['environments'].keys
              elsif stack.key?('attributes')
                [nil]
              else
                [captures.fetch('environment')]
              end
              environments &= [captures['environment']] if captures.key?('environment')
              directory = Entities::PatternMatcher.expand(pattern, captures)
              custom = captures.reject { |key, _| %w[service environment].include?(key) }
              environments.each do |environment|
                identity = [service, stack['id'], environment, directory]
                if candidates.key?(identity) && candidates[identity][:captures] != custom
                  raise "Conflicting captures for stack '#{stack['id']}' at '#{directory}'"
                end
                candidates[identity] = { stack: stack, service: service, environment: environment, captures: custom }
              end
            end
          end
        end

        services = candidates.values.filter_map do |candidate|
          values = candidate.fetch(:captures).merge('service' => candidate.fetch(:service), 'environment' => candidate.fetch(:environment))
          candidate.fetch(:service) unless config.excluded?(candidate.fetch(:stack), values)
        end.uniq
        labels = services.map { |service| Entities::DeployLabel.from_service(service: service) }
        Entities::Result.success(deploy_labels: labels, changed_files: changed_files, services_detected: services)
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end
    end
  end
end
