# Controller for label dispatcher functionality
# Coordinates service detection and label management operations

module Interfaces
  module Controllers
    class LabelDispatcherController
      def initialize(dispatch_labels:, detect_changed_services:, presenter:)
        @dispatch_labels = dispatch_labels
        @detect_changed_services = detect_changed_services
        @presenter = presenter
      end

      def dispatch(pr_number:)
        result = @dispatch_labels.call.execute(pr_number: pr_number)
        return failure(result) if result.failure?

        dispatch = result.value
        present(dispatch.detection, labels_added: dispatch.labels_added, labels_removed: dispatch.labels_removed)
        result
      end

      def test(base_ref:, head_ref:)
        result = @detect_changed_services.execute(base_ref: base_ref, head_ref: head_ref)
        return failure(result) if result.failure?

        present(result.value, labels_added: [], labels_removed: [])
        result
      end

      private

      def present(detection, labels_added:, labels_removed:)
        @presenter.present_label_dispatch_result(
          deploy_labels: detection.deploy_labels,
          labels_added: labels_added,
          labels_removed: labels_removed,
          changed_files: detection.changed_files
        )
      end

      def failure(result)
        @presenter.present_error(result.error_message)
        result
      end
    end
  end
end
