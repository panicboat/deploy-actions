module UseCases
  module LabelManagement
    Dispatch = Data.define(:detection, :labels_added, :labels_removed)
    class DispatchLabels
      def initialize(github_client:, detect_changed_services:, manage_labels:)
        @github_client = github_client
        @detect_changed_services = detect_changed_services
        @manage_labels = manage_labels
      end

      def execute(pr_number:)
        pr_info = begin
          @github_client.get_pr_info(pr_number)
        rescue => error
          return Entities::Result.failure("Failed to get PR info: #{error.message}")
        end

        detection_result = @detect_changed_services.execute(base_ref: pr_info[:base_sha], head_ref: pr_info[:head_sha])
        return detection_result if detection_result.failure?

        detection = detection_result.value
        sync_result = @manage_labels.execute(pr_number: pr_number, required_labels: detection.deploy_labels.map(&:to_s))
        return sync_result if sync_result.failure?

        Entities::Result.success(Dispatch.new(detection: detection, labels_added: sync_result.value.labels_added, labels_removed: sync_result.value.labels_removed))
      end
    end
  end
end
