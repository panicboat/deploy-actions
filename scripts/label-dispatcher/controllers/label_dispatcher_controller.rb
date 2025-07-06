# Controller for label dispatcher functionality
# Coordinates service detection and label management operations

module Interfaces
  module Controllers
    class LabelDispatcherController
      def initialize(
        detect_services_use_case:,
        manage_labels_use_case:,
        presenter:
      )
        @detect_services = detect_services_use_case
        @manage_labels = manage_labels_use_case
        @presenter = presenter
      end

      # Dispatch labels for a PR based on changed files
      def dispatch_labels(pr_number:)
        base_ref = nil
        head_ref = nil

        # If PR number is provided and GitHub API is available, fetch information from API
        if pr_number && @manage_labels
          pr_info = get_pr_info_from_api(pr_number)
          if pr_info[:base_sha] && pr_info[:head_sha]
            base_ref = pr_info[:base_sha]  # Use SHA
            head_ref = pr_info[:head_sha]  # Use SHA
            puts "✅ Using refs from API: base=#{base_ref[0..7]}, head=#{head_ref[0..7]}"
          end
        end

        # Detect changed services (including exclusion filtering)
        detection_result = @detect_services.execute(base_ref: base_ref, head_ref: head_ref)
        return @presenter.present_error(detection_result) if detection_result.failure?

        # Manage labels if in GitHub Actions and PR number provided
        if ENV['GITHUB_ACTIONS'] && pr_number && @manage_labels
          required_labels = detection_result.deploy_labels.map(&:to_s)
          manage_result = @manage_labels.execute(pr_number: pr_number, required_labels: required_labels)
          return @presenter.present_error(manage_result) if manage_result.failure?

          # Prepare excluded services configuration for comment
          excluded_services_config = build_excluded_services_config(detection_result.excluded_services)

          # Update deployment comment with exclusion information
          comment_result = @manage_labels.update_deployment_comment(
            pr_number: pr_number,
            deploy_labels: detection_result.deploy_labels,
            changed_files: detection_result.changed_files,
            excluded_services: detection_result.excluded_services,
            excluded_services_config: excluded_services_config
          )
          # Note: Don't fail if comment update fails, just log it
          if comment_result.failure?
            puts "Warning: Failed to update deployment comment: #{comment_result.error_message}"
          end

          labels_added = manage_result.labels_added
          labels_removed = manage_result.labels_removed
        else
          labels_added = []
          labels_removed = []
        end

        @presenter.present_label_dispatch_result(
          deploy_labels: detection_result.deploy_labels,
          labels_added: labels_added,
          labels_removed: labels_removed,
          changed_files: detection_result.changed_files,
          excluded_services: detection_result.excluded_services || []
        )
      end

      # Test detection without PR interaction
      def test_detection(base_ref: nil, head_ref: nil)
        puts "🧪 Testing deployment workflow for base: #{base_ref}, head: #{head_ref}"

        detection_result = @detect_services.execute(base_ref: base_ref, head_ref: head_ref)
        return @presenter.present_error(detection_result) if detection_result.failure?

        @presenter.present_label_dispatch_result(
          deploy_labels: detection_result.deploy_labels,
          labels_added: [],
          labels_removed: [],
          changed_files: detection_result.changed_files,
          excluded_services: detection_result.excluded_services || []
        )
      end

      # Simulate GitHub Actions environment locally
      def simulate_github_actions(pr_number:)
        puts "🎭 Simulating GitHub Actions environment..."

        # Set up GitHub Actions environment
        original_github_actions = ENV['GITHUB_ACTIONS']
        original_github_env = ENV['GITHUB_ENV']

        ENV['GITHUB_ACTIONS'] = 'true'
        ENV['GITHUB_ENV'] = '/tmp/github_env'
        File.write(ENV['GITHUB_ENV'], '')

        begin
          dispatch_labels(pr_number: pr_number)

          if File.exist?(ENV['GITHUB_ENV'])
            puts "\n📋 Generated Environment Variables:"
            puts File.read(ENV['GITHUB_ENV'])
          end
        ensure
          # Restore original environment
          ENV['GITHUB_ACTIONS'] = original_github_actions
          ENV['GITHUB_ENV'] = original_github_env
          File.delete('/tmp/github_env') if File.exist?('/tmp/github_env')
        end
      end

      private

      # Get PR information from GitHub API
      def get_pr_info_from_api(pr_number)
        # Only execute if GitHub client is available
        github_client = get_github_client
        return {} unless github_client

        puts "🔍 Fetching PR ##{pr_number} information from GitHub API..."
        pr_info = github_client.get_pr_info(pr_number)

        puts "📋 PR Info: #{pr_info[:title]}"
        puts "   Base: #{pr_info[:base_ref]} (#{pr_info[:base_sha][0..7]})"
        puts "   Head: #{pr_info[:head_ref]} (#{pr_info[:head_sha][0..7]})"

        {
          base_ref: pr_info[:base_ref],
          head_ref: pr_info[:head_ref],
          base_sha: pr_info[:base_sha],
          head_sha: pr_info[:head_sha],
          labels: pr_info[:labels]
        }
      rescue => error
        puts "⚠️  Warning: Failed to get PR info from API: #{error.message}"
        puts "   Falling back to manual base/head refs if provided"
        {}
      end

      # Get GitHub Client from manage_labels use case
      def get_github_client
        return nil unless @manage_labels

        # Get GitHub client from manage_labels
        if @manage_labels.respond_to?(:github_client)
          @manage_labels.github_client
        elsif @manage_labels.instance_variable_get(:@github_client)
          @manage_labels.instance_variable_get(:@github_client)
        else
          nil
        end
      end

      # Build excluded services configuration for comment display
      def build_excluded_services_config(excluded_services)
        return {} if excluded_services.nil? || excluded_services.empty?

        # In a real implementation, this would get the configuration from the config client
        # For now, we'll create a simplified version
        config = {}

        # Load configuration to get exclusion details
        # Note: This is a simplified approach - in practice, we'd need to access
        # the config client or pass this information from the detection result
        begin
          config_client = Infrastructure::ConfigClient.new
          workflow_config = config_client.load_workflow_config

          excluded_services.each do |service|
            service_config = workflow_config.services[service]
            if service_config && service_config['exclusion_config']
              config[service] = {
                reason: service_config['exclusion_config']['reason'] || 'Manual deployment required',
                type: service_config['exclusion_config']['type'] || 'unspecified'
              }
            else
              config[service] = {
                reason: 'Manual deployment required',
                type: 'unspecified'
              }
            end
          end
        rescue => error
          puts "Warning: Could not load exclusion config details: #{error.message}"
          # Fallback to default configuration
          excluded_services.each do |service|
            config[service] = {
              reason: 'Manual deployment required',
              type: 'unspecified'
            }
          end
        end

        config
      end
    end
  end
end
