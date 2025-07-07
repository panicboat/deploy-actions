# spec/config-manager/use_cases/validate_config_spec.rb

require 'spec_helper'

RSpec.describe UseCases::ConfigManagement::ValidateConfig do
  let(:config_client) { double('ConfigClient') }
  subject(:use_case) { described_class.new(config_client: config_client) }

  describe '#execute' do
    context 'with valid configuration' do
      let(:config) { build(:workflow_config) }
      let(:validation_result) do
        double(
          'Result',
          success?: true,
          config: config,
          validation_summary: 'All checks passed'
        )
      end

      before do
        allow(config_client).to receive(:validate_config_file).and_return(validation_result)
      end

      it 'returns successful result with config and summary' do
        result = use_case.execute

        expect(result).to be_success
        expect(result.config).to eq(config)
        expect(result.validation_summary).to eq('All checks passed')
      end
    end

    context 'with invalid configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: ['Missing environments', 'Invalid service configuration'],
          error_message: 'Configuration validation failed'
        )
      end

      before do
        allow(config_client).to receive(:validate_config_file).and_return(validation_result)
      end

      it 'returns failure result with validation errors' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.validation_errors).to eq(['Missing environments', 'Invalid service configuration'])
        expect(result.error_message).to eq('Configuration validation failed')
      end
    end

    context 'with configuration file not found' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: nil,
          error_message: 'Configuration file not found'
        )
      end

      before do
        allow(config_client).to receive(:validate_config_file).and_return(validation_result)
      end

      it 'returns failure result with file error' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.error_message).to eq('Configuration file not found')
      end
    end

    context 'with config client exception' do
      let(:error) { StandardError.new('Unexpected error during validation') }

      before do
        allow(config_client).to receive(:validate_config_file).and_raise(error)
      end

      it 'handles exceptions and returns failure result' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.error_message).to include('Unexpected error during validation')
      end
    end

    context 'with comprehensive validation checks' do
      let(:config) { build(:workflow_config, :with_excluded_service) }
      let(:validation_result) do
        double(
          'Result',
          success?: true,
          config: config,
          validation_summary: build_validation_summary(config)
        )
      end

      before do
        allow(config_client).to receive(:validate_config_file).and_return(validation_result)
      end

      it 'includes detailed validation information' do
        result = use_case.execute

        expect(result).to be_success
        expect(result.validation_summary).to include('environments: 3 configured')
        expect(result.validation_summary).to include('services: 2 configured')
        expect(result.validation_summary).to include('excluded services: 1')
      end

      def build_validation_summary(config)
        env_count = config.environments.length
        service_count = config.services.length
        excluded_count = config.excluded_services.length

        [
          "✅ Configuration validation successful",
          "📋 Summary:",
          "  - environments: #{env_count} configured",
          "  - services: #{service_count} configured (#{excluded_count} excluded)",
          "  - directory conventions: #{config.raw_config.dig('directory_conventions', 'stacks')&.length || 0} stacks",
          "  - branch patterns: #{config.branch_patterns.length} configured"
        ].join("\n")
      end
    end

    context 'with empty configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: [
            'Missing required section: environments',
            'Missing required section: directory_conventions',
            'Missing required section: services'
          ],
          error_message: 'Configuration is incomplete'
        )
      end

      before do
        allow(config_client).to receive(:validate_config_file).and_return(validation_result)
      end

      it 'reports all missing sections' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.validation_errors).to include(
          match(/environments/),
          match(/directory_conventions/),
          match(/services/)
        )
      end
    end
  end

  describe 'integration with real config client' do
    let(:real_config_client) { Infrastructure::ConfigClient.new }
    let(:use_case) { described_class.new(config_client: real_config_client) }
    let(:temp_config) { create_test_config(config_content) }

    after { temp_config.unlink if temp_config }

    context 'with valid real configuration' do
      let(:config_content) { default_test_config }

      it 'successfully validates real configuration' do
        result = use_case.execute

        expect(result).to be_success
        expect(result.config).to be_a(Entities::WorkflowConfig)
        expect(result.validation_summary).to be_present
      end
    end

    context 'with invalid real configuration' do
      let(:config_content) do
        <<~YAML
          # Missing required sections
          invalid_section:
            - some_data
        YAML
      end

      it 'properly validates and reports errors' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.validation_errors).to be_present
      end
    end
  end
end