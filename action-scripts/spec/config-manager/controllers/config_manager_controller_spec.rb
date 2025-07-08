# spec/config-manager/controllers/config_manager_controller_spec.rb

require 'spec_helper'

RSpec.describe Interfaces::Controllers::ConfigManagerController do
  let(:validate_config_use_case) { double('ValidateConfig') }
  let(:config_client) { double('ConfigClient') }
  let(:presenter) { double('Presenter') }

  subject(:controller) do
    described_class.new(
      validate_config_use_case: validate_config_use_case,
      config_client: config_client,
      presenter: presenter
    )
  end

  describe '#validate_configuration' do
    context 'with valid configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: true,
          config: build(:workflow_config),
          validation_summary: 'Configuration is valid'
        )
      end

      it 'presents successful validation result' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: true,
          config: validation_result.config,
          summary: 'Configuration is valid'
        )
      end
    end

    context 'with invalid configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: ['Missing required field: environments'],
          error_message: 'Validation failed'
        )
      end

      it 'presents validation errors' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: false,
          errors: ['Missing required field: environments']
        )
      end
    end

    context 'with validation error but no specific errors' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: nil,
          error_message: 'General validation error'
        )
      end

      it 'uses error message as fallback' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: false,
          errors: ['General validation error']
        )
      end
    end
  end

  describe '#show_configuration' do
    context 'with successful config loading' do
      let(:config) { build(:workflow_config) }

      it 'presents configuration details' do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
        allow(presenter).to receive(:present_config_details)

        controller.show_configuration

        expect(presenter).to have_received(:present_config_details).with(config: config)
      end
    end

    context 'with config loading error' do
      let(:error) { StandardError.new('Config file not found') }

      it 'presents error result' do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
        allow(presenter).to receive(:present_error)

        controller.show_configuration

        expect(presenter).to have_received(:present_error) do |result|
          expect(result.failure?).to be true
          expect(result.error_message).to include('Config file not found')
        end
      end
    end
  end

  describe '#test_service_configuration' do
    let(:config) { build(:workflow_config) }
    let(:service_name) { 'test-service' }
    let(:environment) { 'develop' }

    context 'with valid service and environment' do
      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
        allow(config).to receive_message_chain(:services, :key?).with(service_name).and_return(true)
        allow(config).to receive_message_chain(:environments, :key?).with(environment).and_return(true)
        allow(config).to receive(:environment_config).with(environment).and_return({
          'environment' => environment,
          'aws_region' => 'ap-northeast-1'
        })
        allow(config).to receive_message_chain(:services, :[]).with(service_name).and_return({
          'name' => service_name
        })
        allow(config).to receive(:directory_convention_for).and_return('services/{service}/terragrunt/envs/{environment}')
        allow(presenter).to receive(:present_service_test_result)
      end

      it 'presents service test result' do
        controller.test_service_configuration(service_name: service_name, environment: environment)

        expect(presenter).to have_received(:present_service_test_result).with(
          service_name: service_name,
          environment: environment,
          env_config: hash_including('environment' => environment),
          service_config: hash_including('name' => service_name),
          terragrunt_directory: 'services/test-service/terragrunt/envs/develop',
          kubernetes_directory: 'services/test-service/kubernetes/overlays/develop'
        )
      end
    end

    context 'with non-existing service' do
      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
        allow(config).to receive_message_chain(:services, :key?).with(service_name).and_return(false)
        allow(presenter).to receive(:present_error)
      end

      it 'presents service not found error' do
        controller.test_service_configuration(service_name: service_name, environment: environment)

        expect(presenter).to have_received(:present_error) do |result|
          expect(result.failure?).to be true
          expect(result.error_message).to include("Service '#{service_name}' not found")
        end
      end
    end

    context 'with non-existing environment' do
      before do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
        allow(config).to receive_message_chain(:services, :key?).with(service_name).and_return(true)
        allow(config).to receive_message_chain(:environments, :key?).with(environment).and_return(false)
        allow(presenter).to receive(:present_error)
      end

      it 'presents environment not found error' do
        controller.test_service_configuration(service_name: service_name, environment: environment)

        expect(presenter).to have_received(:present_error) do |result|
          expect(result.failure?).to be true
          expect(result.error_message).to include("Environment '#{environment}' not found")
        end
      end
    end
  end

  describe '#run_diagnostics' do
    let(:config) { build(:workflow_config) }

    before do
      allow(validate_config_use_case).to receive(:execute).and_return(build(:result_success))
      allow(presenter).to receive(:present_diagnostic_results)
      allow(File).to receive(:exist?).and_return(true)
      
      # Mock git status
      allow(controller).to receive(:`).with('git status --porcelain 2>/dev/null').and_return('')
      allow(controller).to receive(:$?).and_return(double(success?: true))
      
      # Mock environment variables
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('test_token')
      allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return('test/repo')
    end

    it 'runs comprehensive diagnostic checks' do
      controller.run_diagnostics

      expect(presenter).to have_received(:present_diagnostic_results) do |args|
        results = args[:results]
        expect(results).to be_an(Array)
        expect(results.length).to eq(4)
        
        # Check that all diagnostic checks are included
        check_names = results.map { |r| r[:check] }
        expect(check_names).to include(
          'Configuration Validation',
          'Environment Variables',
          'Git Repository',
          'Configuration File'
        )
      end
    end

    context 'with missing environment variables' do
      before do
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
      end

      it 'reports missing environment variables' do
        controller.run_diagnostics

        expect(presenter).to have_received(:present_diagnostic_results) do |args|
          env_check = args[:results].find { |r| r[:check] == 'Environment Variables' }
          expect(env_check[:status]).to eq('FAIL')
          expect(env_check[:details]).to include('GITHUB_TOKEN')
        end
      end
    end
  end

  describe '#generate_config_template' do
    it 'presents generated configuration template' do
      allow(presenter).to receive(:present_config_template)

      controller.generate_config_template

      expect(presenter).to have_received(:present_config_template) do |args|
        template = args[:template]
        expect(template).to be_a(String)
        expect(template).to include('environments:')
        expect(template).to include('directory_conventions:')
        expect(template).to include('services:')
      end
    end
  end
end