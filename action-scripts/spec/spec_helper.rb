# RSpec configuration for action-scripts testing

require 'bundler/setup'
require 'rspec'
require 'webmock/rspec'
require 'vcr'
require 'factory_bot'

# Load shared components
require_relative '../shared/shared_loader'

# Load all modules for testing
[
  'config-manager/**/*.rb',
  'deploy-resolver/**/*.rb',
  'label-dispatcher/**/*.rb'
].each do |pattern|
  Dir[File.expand_path("../#{pattern}", __dir__)].sort.each { |file| require file }
end

RSpec.configure do |config|
  # Use the expect syntax
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Use the new mock syntax
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Random order for tests
  config.order = :random
  Kernel.srand config.seed

  # Filter lines for better error reporting
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!

  # Shared examples and helpers
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Include factory_bot methods
  config.include FactoryBot::Syntax::Methods

  # Configure factory_bot
  config.before(:suite) do
    FactoryBot.find_definitions
  end

  # Clean up environment variables after each test
  config.after(:each) do
    # Restore original environment variables if modified
    ENV.delete('WORKFLOW_CONFIG_PATH')
    ENV.delete('TEST_MODE')
  end

  # Configure VCR for recording HTTP interactions
  config.before(:suite) do
    VCR.configure do |vcr_config|
      vcr_config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
      vcr_config.hook_into :webmock
      vcr_config.configure_rspec_metadata!
      vcr_config.default_cassette_options = {
        record: :once,
        allow_unused_http_interactions: false
      }
      
      # Filter sensitive data
      vcr_config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV['GITHUB_TOKEN'] }
      vcr_config.filter_sensitive_data('<GITHUB_REPOSITORY>') { ENV['GITHUB_REPOSITORY'] }
    end
  end

  # WebMock configuration
  WebMock.disable_net_connect!(allow_localhost: true)
end

# Test helper methods
module SpecHelpers
  # Create a temporary configuration file for testing
  def create_test_config(content)
    temp_file = Tempfile.new(['workflow-config', '.yaml'])
    temp_file.write(content)
    temp_file.close
    ENV['WORKFLOW_CONFIG_PATH'] = temp_file.path
    temp_file
  end

  # Default test configuration
  def default_test_config
    <<~YAML
      environments:
        - environment: develop
          aws_region: ap-northeast-1
          iam_role_plan: arn:aws:iam::123456789012:role/plan-role
          iam_role_apply: arn:aws:iam::123456789012:role/apply-role
        - environment: staging
          aws_region: ap-northeast-1
          iam_role_plan: arn:aws:iam::123456789012:role/staging-plan-role
          iam_role_apply: arn:aws:iam::123456789012:role/staging-apply-role
        - environment: production
          aws_region: ap-northeast-1
          iam_role_plan: arn:aws:iam::123456789012:role/production-plan-role
          iam_role_apply: arn:aws:iam::123456789012:role/production-apply-role

      directory_conventions:
        root: "{service}"
        stacks:
          - name: terragrunt
            directory: "terragrunt/{environment}"
          - name: kubernetes
            directory: "kubernetes/overlays/{environment}"

      services:
        - name: test-service
          directory_conventions:
            terragrunt: "services/{service}/terragrunt/envs/{environment}"
        - name: excluded-service
          exclude_from_automation: true
          exclusion_config:
            reason: "Manual deployment required"
            type: "permanent"

      branch_patterns:
        develop: develop
        staging: staging
        production: production
    YAML
  end

  # Mock GitHub API responses
  def mock_github_api
    # Mock PR info response
    stub_request(:get, %r{https://api\.github\.com/repos/.+/pulls/\d+})
      .to_return(
        status: 200,
        body: {
          number: 123,
          title: "Test PR",
          state: "open",
          head: {
            ref: "feature/test",
            sha: "abc123def456"
          },
          base: {
            ref: "main",
            sha: "def456abc123"
          },
          labels: [
            { name: "deploy:test-service" },
            { name: "enhancement" }
          ]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    # Mock labels update response
    stub_request(:put, %r{https://api\.github\.com/repos/.+/issues/\d+/labels})
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Set up test environment variables
  def setup_test_env
    ENV['GITHUB_TOKEN'] = 'test_token'
    ENV['GITHUB_REPOSITORY'] = 'test/repo'
    ENV['TEST_MODE'] = 'true'
  end

  # Clean up test environment
  def cleanup_test_env
    ENV.delete('GITHUB_TOKEN')
    ENV.delete('GITHUB_REPOSITORY')
    ENV.delete('TEST_MODE')
    ENV.delete('WORKFLOW_CONFIG_PATH')
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
end