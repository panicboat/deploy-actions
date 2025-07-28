# spec/config-manager/use_cases/validate_config_spec.rb

require 'spec_helper'

RSpec.describe UseCases::ConfigManagement::ValidateConfig do
  let(:config_client) { double('ConfigClient') }
  subject(:use_case) { described_class.new(config_client: config_client) }

  describe '#execute' do
    context 'with valid configuration' do
      let(:config) { build(:workflow_config) }

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'returns successful result with config and summary' do
        result = use_case.execute

        expect(result).to be_success
        expect(result.config).to eq(config)
        expect(result.validation_summary).to include('Configuration validation successful')
      end
    end

    context 'with invalid configuration' do
      let(:config) do
        Entities::WorkflowConfig.new({
          'environments' => [],
          'services' => [],
          'directory_conventions' => [
            {
              'root' => '{service}',
              'stacks' => []
            }
          ]
        })
      end

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'returns failure result with validation errors' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.validation_errors).to include('No environments defined')
        expect(result.error_message).to include('Configuration validation failed')
      end
    end

    context 'with configuration file not found' do
      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(StandardError.new('Configuration file not found'))
      end

      it 'returns failure result with file error' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.error_message).to eq('Failed to load or validate configuration: Configuration file not found')
      end
    end

    context 'with config client exception' do
      let(:error) { StandardError.new('Unexpected error during validation') }

      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
      end

      it 'handles exceptions and returns failure result' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.error_message).to include('Failed to load or validate configuration: Unexpected error during validation')
      end
    end

    context 'with comprehensive validation checks' do
      let(:config) { build(:workflow_config, :with_excluded_service) }

      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
      end

      it 'includes detailed validation information' do
        result = use_case.execute

        expect(result).to be_success
        expect(result.validation_summary).to include('environments: 3 configured')
        expect(result.validation_summary).to include('services: 2 configured')
        expect(result.validation_summary).to include('excluded')
      end
    end

    context 'with empty configuration' do
      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(
          StandardError.new('Configuration validation failed: Missing required configuration sections: directory_conventions')
        )
      end

      it 'reports all missing sections' do
        result = use_case.execute

        expect(result).to be_failure
        expect(result.error_message).to include('Configuration validation failed')
        expect(result.error_message).to include('directory_conventions')
      end
    end
  end

  describe 'integration with real config client' do
    let(:real_config_client) { Infrastructure::ConfigClient.new(config_path: temp_config.path) }
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