# Use case for retrieving labels from PR

module UseCases
  module LabelResolver
    class GetLabels
      def initialize(github_client:, config_client:)
        @github_client = github_client
        @config_client = config_client
      end

      # Execute PR label retrieval with PR number
      def execute(pr_number:)
        prefixes = @config_client.load_workflow_config.label_prefixes
        pr_info = @github_client.get_pr_info(pr_number)
        deploy_labels_strings = pr_info[:labels].select { |label| prefixes.any? { |prefix| label.start_with?(prefix) } }

        deploy_labels = deploy_labels_strings.map { |label| Entities::DeployLabel.new(label, prefixes: prefixes) }.select(&:valid?)

        Entities::Result.success(
          pr_number: pr_number,
          deploy_labels: deploy_labels,
          raw_labels: deploy_labels_strings,
        )
      rescue => error
        Entities::Result.failure(error_message: "Failed to retrieve PR labels: #{error.message}")
      end
    end
  end
end
