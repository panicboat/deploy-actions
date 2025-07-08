# Controller for deploy resolver functionality

module Interfaces
  module Controllers
    class DeployResolverController
      def initialize(
        determine_target_environment_use_case:,
        get_labels_use_case:,
        validate_deployment_safety_use_case:,
        generate_matrix_use_case:,
        presenter:
      )
        @determine_target_environment = determine_target_environment_use_case
        @get_labels = get_labels_use_case
        @validate_deployment_safety = validate_deployment_safety_use_case
        @generate_matrix = generate_matrix_use_case
        @presenter = presenter
      end

      # Resolve deployment from PR labels using current branch
      def resolve_from_labels(pr_number:)
        current_branch = ENV['GITHUB_REF_NAME'] || 'develop'

        # Step 1: Get labels from specific PR
        pr_result = get_pr_labels_directly(pr_number)
        return @presenter.present_error(pr_result) if pr_result.failure?

        deploy_labels = pr_result.deploy_labels

        # Step 2: Determine target environment from current branch
        env_result = @determine_target_environment.execute(branch_name: current_branch)
        return @presenter.present_error(env_result) if env_result.failure?

        target_environment = env_result.target_environment

        # Step 3: Validate deployment safety
        safety_result = @validate_deployment_safety.execute(
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          branch_name: current_branch
        )
        return @presenter.present_error(safety_result) if safety_result.failure?

        # Step 4: Generate deployment matrix
        matrix_result = @generate_matrix.execute(
          deploy_labels: deploy_labels,
          target_environment: target_environment
        )
        return @presenter.present_error(matrix_result) if matrix_result.failure?

        # Present results
        @presenter.present_deployment_matrix(
          deployment_targets: matrix_result.deployment_targets,
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          branch_name: current_branch,
          target_environment: target_environment,
          safety_status: safety_result.safety_status
        )
      end

      # Test deployment workflow without actual execution
      def test_deployment_workflow(pr_number:)
        puts "🧪 Testing deployment workflow for PR: #{pr_number}"

        begin
          resolve_from_labels(pr_number: pr_number)
        rescue => error
          puts "Test completed with error (expected in test mode): #{error.message}"
        end
      end

      # Simulate GitHub Actions environment for testing
      def simulate_github_actions(pr_number:)
        puts "🎭 Simulating GitHub Actions environment..."

        original_github_actions = ENV['GITHUB_ACTIONS']
        original_github_env = ENV['GITHUB_ENV']

        ENV['GITHUB_ACTIONS'] = 'true'
        ENV['GITHUB_ENV'] = '/tmp/github_env'
        File.write(ENV['GITHUB_ENV'], '')

        begin
          resolve_from_labels(pr_number: pr_number)

          if File.exist?(ENV['GITHUB_ENV'])
            puts "\n📋 Generated Environment Variables:"
            puts File.read(ENV['GITHUB_ENV'])
          end
        rescue => error
          puts "🧪 Test completed with error: #{error.message}"
        ensure
          ENV['GITHUB_ACTIONS'] = original_github_actions
          ENV['GITHUB_ENV'] = original_github_env
          File.delete('/tmp/github_env') if File.exist?('/tmp/github_env')
        end
      end

      # Debug deployment workflow step by step
      def debug_deployment_workflow(pr_number:)
        current_branch = ENV['GITHUB_REF_NAME'] || 'develop'
        
        puts "Step 1: Getting PR labels..."
        pr_result = get_pr_labels_directly(pr_number)
        if pr_result.failure?
          puts "❌ Failed to get PR labels: #{pr_result.error_message}"
          return
        end
        
        puts "✅ Found #{pr_result.deploy_labels.length} deploy labels: #{pr_result.deploy_labels.map(&:to_s)}"
        
        puts "\nStep 2: Determining target environment from current branch (#{current_branch})..."
        env_result = @determine_target_environment.execute(branch_name: current_branch)
        if env_result.failure?
          puts "❌ Failed to determine environment: #{env_result.error_message}"
          return
        end
        
        puts "✅ Target environment: #{env_result.target_environment}"
        
        puts "\nStep 3: Validating deployment safety..."
        safety_result = @validate_deployment_safety.execute(
          deploy_labels: pr_result.deploy_labels,
          pr_number: pr_number,
          branch_name: current_branch
        )
        if safety_result.failure?
          puts "❌ Safety validation failed: #{safety_result.error_message}"
          return
        end
        
        puts "✅ Safety validation passed: #{safety_result.safety_status}"
        
        puts "\nStep 4: Generating deployment matrix..."
        matrix_result = @generate_matrix.execute(
          deploy_labels: pr_result.deploy_labels,
          target_environment: env_result.target_environment
        )
        if matrix_result.failure?
          puts "❌ Matrix generation failed: #{matrix_result.error_message}"
          return
        end
        
        puts "✅ Generated #{matrix_result.deployment_targets.length} deployment targets:"
        matrix_result.deployment_targets.each do |target|
          puts "  - #{target.service}:#{target.environment}:#{target.stack} (#{target.working_directory})"
        end
        
        puts "\n🎯 Debug completed successfully!"
      end

      private

      # Get PR labels directly without searching
      def get_pr_labels_directly(pr_number)
        unless @get_labels
          return Entities::Result.failure(error_message: "GitHub client not available")
        end

        @get_labels.execute(pr_number: pr_number)
      end
    end
  end
end
