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
        shared = []
        changed_files.each do |file|
          config.services.each do |service_config|
            service_config['roots'].each_with_index do |root, root_index|
              root_captures = Entities::PatternMatcher.extract_prefix(root, file)
              next unless root_captures
              service = root_captures.fetch('service')
              next if service.start_with?('.')
              relative_path = file.delete_prefix("#{Entities::PatternMatcher.expand(root, root_captures)}/")
              next if config.ignored?(service_config, relative_path)
              in_stack = false
              service_config['stacks'].each do |stack|
                pattern = stack['paths'][root_index]
                captures = Entities::PatternMatcher.extract_prefix(pattern, file)
                next unless captures
                environments = if stack.key?('environments')
                  stack['environments'].keys
                elsif stack['common']
                  [nil]
                else
                  [captures.fetch('environment')]
                end
                environments &= [captures['environment']] if captures.key?('environment')
                next if environments.empty?
                # A dot path holds every file under the root, so counting it would stop shared-file detection for the other stacks.
                in_stack = true unless stack['path'].empty?
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
              shared << service unless in_stack
            end
          end
        end

        services = (shared + candidates.values.filter_map do |candidate|
          values = candidate.fetch(:captures).merge('service' => candidate.fetch(:service), 'environment' => candidate.fetch(:environment))
          candidate.fetch(:service) unless config.excluded?(candidate.fetch(:stack), values)
        end).uniq
        labels = services.map { |service| Entities::DeployLabel.from_service(service: service, prefix: config.label_prefix) }
        Entities::Result.success(deploy_labels: labels, changed_files: changed_files, services_detected: services)
      rescue => error
        Entities::Result.failure(error_message: error.message)
      end
    end
  end
end
