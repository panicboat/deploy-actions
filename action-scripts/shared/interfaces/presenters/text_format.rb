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

      def deployment_matrix(deployment_targets:, deploy_labels:, target_environments: nil, pr_number: nil)
        lines = ['🚀 Deployment Matrix']
        if target_environments && target_environments.length > 1
          lines << "Target Environments: #{target_environments.join(', ')}"
        elsif target_environments && target_environments.length == 1
          lines << "Target Environment: #{target_environments.first}"
        end
        lines << "PR Number: ##{pr_number}" if pr_number
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

      def service_targets(service:, target_environments:, targets:, candidates:)
        lines = ['🎯 Service Targets', "Service: #{service}"]
        if target_environments.length > 1
          lines << "Target Environments: #{target_environments.join(', ')}"
        elsif target_environments.length == 1
          lines << "Target Environment: #{target_environments.first}"
        end
        lines << "Targets: #{targets.length} of #{candidates.length} candidates"
        candidates.each do |listed|
          target = listed.target
          environment = target.environment && " (#{target.environment})"
          lines << '' << "  #{target.service}:#{target.stack}#{environment} -> #{target.working_directory}"
          lines << "    root: #{listed.root}" << "    excluded: #{listed.excluded?}"
        end
        lines
      end

      def config_validation(valid:, errors:, summary:)
        return ['❌ Configuration validation failed', *errors.map { |error| "  - #{error}" }] unless valid

        lines = ['✅ Configuration is valid']
        lines.push('Summary:', summary) if summary
        lines
      end

      def service_test_result(service_name:, candidates:)
        lines = ['Service Configuration Test', "Service: #{service_name}"]
        candidates.each do |candidate|
          lines << 'Target:'
          lines.concat(candidate.to_deployment_target.to_matrix_item.map { |key, value| "  #{key}: #{value.inspect}" })
          lines << "  excluded: #{candidate.excluded?}"
        end
        lines
      end
    end
  end
end
