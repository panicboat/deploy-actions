module Interfaces
  module Presenters
    module TextFormat
      module_function

      def label_dispatch(deploy_labels:, labels_added:, labels_removed:, changed_files:)
        lines = ['🏷️  Label Dispatch Results', "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"]
        lines << "Labels Added: #{labels_added.join(', ')}" if labels_added.any?
        lines << "Labels Removed: #{labels_removed.join(', ')}" if labels_removed.any?
        lines << "Changed Files: #{changed_files.length} files"
        if changed_files.length <= 10
          lines.concat(changed_files.map { |file| "  - #{file}" })
        else
          lines << '  (showing first 10 files)'
          lines.concat(changed_files.first(10).map { |file| "  - #{file}" })
          lines << "  ... and #{changed_files.length - 10} more files"
        end
        lines
      end

      def deployment_matrix(deployment_targets:, deploy_labels:, target_environment: nil, target_environments: nil, merged_pr_number: nil, pr_number: nil, safety_status: nil)
        lines = ['🚀 Deployment Matrix']
        if target_environments && target_environments.length > 1
          lines << "Target Environments: #{target_environments.join(', ')}"
        elsif target_environment
          lines << "Target Environment: #{target_environment}"
        elsif target_environments && target_environments.length == 1
          lines << "Target Environment: #{target_environments.first}"
        end
        lines << "PR Number: ##{merged_pr_number || pr_number}" if merged_pr_number || pr_number
        lines << "Safety Status: #{safety_status}" if safety_status
        lines << ''
        lines << "Deploy Labels: #{deploy_labels.map(&:to_s).join(', ')}"
        lines << "Deployment Targets: #{deployment_targets.length}"
        deployment_targets.group_by(&:environment).each do |env, targets|
          lines << '' << "  Environment: #{env}"
          targets.each do |target|
            lines << "    #{target.service}:#{target.stack} -> #{target.working_directory}"
            lines.concat(target.attributes.map { |key, value| "      #{key}: #{value}" })
          end
        end
        lines << ''
      end

      def config_details(config:)
        lines = ['Workflow Configuration', "Environments: #{config.declared_environment_names.join(', ')}"]
        config.services.each do |service|
          lines << "Service '#{service.id}':"
          lines << "  roots: #{service.roots.join(', ')}"
          lines << "  ignore: #{service.ignore.join(', ')}" unless service.ignore.empty?
          service.stacks.each do |stack|
            lines << "  Stack '#{stack.id}':"
            # Psych writes the root path as '' and would quote a bare dot, so the line is replaced as text.
            details = stack.to_h.slice(:path, :paths, :attributes, :exclude, :environments).compact.transform_keys(&:to_s).to_yaml.sub(/^path: ''$/, 'path: .')
            lines.concat(details.lines.drop(1).map { |line| "    #{line.chomp}" })
          end
        end
        lines
      end

      def service_test_result(service_name:, matches:)
        lines = ['Service Configuration Test', "Service: #{service_name}"]
        matches.each do |match|
          lines << 'Target:'
          lines.concat(match.fetch(:target).to_matrix_item.map { |key, value| "  #{key}: #{value.inspect}" })
          lines << "  excluded: #{match.fetch(:excluded)}"
        end
        lines
      end
    end
  end
end
