# spec/label-resolver/use_cases/generate_matrix_spec.rb

require 'spec_helper'

RSpec.describe UseCases::LabelResolver::GenerateMatrix do
  let(:config_client) { double('ConfigClient') }
  let(:config) { build(:workflow_config) }

  subject(:use_case) { described_class.new(config_client: config_client) }

  before do
    allow(config_client).to receive(:load_workflow_config).and_return(config)
  end

  describe '#execute' do
    let(:target_environment) { 'develop' }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }

    context 'with valid service labels' do
      let(:env_config) do
        {
          'environment' => 'develop',
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        }
      end

      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return(env_config)
        allow(config).to receive(:directory_convention_for).with('test-service', 'terragrunt').and_return('test-service/terragrunt/{environment}')
        allow(config).to receive(:directory_convention_for).with('test-service', 'kubernetes').and_return('test-service/kubernetes/overlays/{environment}')
        allow(config).to receive(:directory_conventions_root).and_return('{service}')

        # Mock new directory structure
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])

        # Mock service existence check and services hash access
        services_mock = { 'test-service' => {} }
        allow(config).to receive(:services).and_return(services_mock)

        # Mock directory existence checks
        allow(File).to receive(:directory?).and_return(true)
      end

      it 'generates deployment targets for both stacks' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets.length).to eq(2)

        terragrunt_target = result.deployment_targets.find { |t| t.stack == 'terragrunt' }
        kubernetes_target = result.deployment_targets.find { |t| t.stack == 'kubernetes' }

        expect(terragrunt_target).not_to be_nil
        expect(terragrunt_target.service).to eq('test-service')
        expect(terragrunt_target.environment).to eq('develop')
        expect(terragrunt_target.working_directory).to eq('test-service/terragrunt/develop')
        expect(terragrunt_target.directory_conventions_root).to eq('test-service')

        expect(kubernetes_target).not_to be_nil
        expect(kubernetes_target.service).to eq('test-service')
        expect(kubernetes_target.environment).to eq('develop')
        expect(kubernetes_target.working_directory).to eq('test-service/kubernetes/overlays/develop')
        expect(kubernetes_target.directory_conventions_root).to eq('test-service')
      end
    end

    context 'with deploy:all label' do
      let(:deploy_labels) { [build(:deploy_label, :valid_all)] }

      before do
        # Mock directory stacks
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])

        # Mock all services
        services_mock = {
          'service1' => {},
          'service2' => {},
          'excluded-service' => { 'exclude_from_automation' => true }
        }
        allow(config).to receive(:services).and_return(services_mock)
        allow(config).to receive(:excluded_services).and_return(['excluded-service'])
        allow(config).to receive(:environment_config).with(target_environment).and_return({
          'environment' => 'develop',
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        })
        allow(config).to receive(:directory_conventions_root).and_return('{service}')

        # Mock directory conventions for both services
        ['service1', 'service2'].each do |service|
          allow(config).to receive(:directory_convention_for).with(service, 'terragrunt').and_return("#{service}/terragrunt/{environment}")
          allow(config).to receive(:directory_convention_for).with(service, 'kubernetes').and_return("#{service}/kubernetes/overlays/{environment}")
        end

        # Mock directory existence checks
        allow(File).to receive(:directory?).and_return(true)
      end

      it 'generates targets for all non-excluded services' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets.length).to eq(4) # 2 services × 2 stacks

        service_names = result.deployment_targets.map(&:service).uniq
        expect(service_names).to contain_exactly('service1', 'service2')
        expect(service_names).not_to include('excluded-service')
      end
    end

    context 'with non-existent environment' do
      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return(nil)
      end

      it 'returns failure result' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_failure
        expect(result.error_message).to include('Environment configuration not found')
        expect(result.error_message).to include(target_environment)
      end
    end

    context 'with non-existent service' do
      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return({
          'environment' => 'develop'
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
        ])
        allow(config).to receive(:services).and_return({})
      end

      it 'skips non-existent services' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets).to be_empty
      end
    end

    context 'with empty deploy labels' do
      let(:deploy_labels) { [] }

      it 'returns empty deployment targets' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets).to be_empty
      end
    end

    context 'with missing directory conventions' do
      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return({
          'environment' => 'develop'
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])
        allow(config).to receive(:services).and_return({ 'test-service' => {} })
        allow(config).to receive(:directory_convention_for).with('test-service', 'terragrunt').and_return(nil)
        allow(config).to receive(:directory_convention_for).with('test-service', 'kubernetes').and_return(nil)
      end

      it 'skips services without directory conventions' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets).to be_empty
      end
    end

    context 'with service-specific directory conventions' do
      let(:env_config) do
        {
          'environment' => 'develop',
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        }
      end

      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return(env_config)
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])
        allow(config).to receive(:services).and_return({ 'test-service' => {} })
        allow(config).to receive(:excluded_services).and_return([])
        allow(config).to receive(:directory_convention_for).with('test-service', 'terragrunt').and_return('custom/{service}/terraform/environments/{environment}')
        allow(config).to receive(:directory_convention_for).with('test-service', 'kubernetes').and_return(nil) # Only terragrunt
        allow(config).to receive(:directory_conventions_for).with('test-service', 'terragrunt').and_return(['custom/{service}/terraform/environments/{environment}'])
        allow(config).to receive(:directory_conventions_for).with('test-service', 'kubernetes').and_return([]) # Only terragrunt

        # Mock directory existence checks
        allow(File).to receive(:directory?).and_return(true)
      end

      it 'uses service-specific conventions and creates only matching targets' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets.length).to eq(1)

        target = result.deployment_targets.first
        expect(target.stack).to eq('terragrunt')
        expect(target.working_directory).to eq('custom/test-service/terraform/environments/develop')
        expect(target.directory_conventions_root).to eq('test-service')
      end
    end

    context 'when config loading fails' do
      let(:error) { StandardError.new('Config file not found') }

      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
      end

      it 'handles error and returns failure result' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_failure
        expect(result.error_message).to include('Matrix generation failed')
        expect(result.error_message).to include('Config file not found')
      end
    end

    context 'with mixed valid and invalid labels' do
      let(:deploy_labels) do
        [
          build(:deploy_label, :valid_service),
          build(:deploy_label, :invalid)
        ]
      end

      before do
        allow(config).to receive(:environment_config).with(target_environment).and_return({
          'environment' => 'develop',
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        })
        allow(config).to receive(:directory_conventions_root).and_return('{service}')
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])
        allow(config).to receive(:services).and_return({ 'test-service' => {} })
        allow(config).to receive(:directory_convention_for).with('test-service', 'terragrunt').and_return('test-service/terragrunt/{environment}')
        allow(config).to receive(:directory_convention_for).with('test-service', 'kubernetes').and_return('test-service/kubernetes/overlays/{environment}')

        # Mock directory existence checks
        allow(File).to receive(:directory?).and_return(true)
      end

      it 'processes only valid deploy labels' do
        result = use_case.execute(deploy_labels: deploy_labels, target_environment: target_environment)

        expect(result).to be_success
        expect(result.deployment_targets.length).to eq(2) # Only test-service targets
        expect(result.deployment_targets.map(&:service).uniq).to eq(['test-service'])
      end
    end
  end

  describe 'integration with real configuration' do
    let(:real_config_client) { Infrastructure::ConfigClient.new }
    let(:use_case) { described_class.new(config_client: real_config_client) }
    let(:temp_config) { create_test_config(default_test_config) }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }

    after { temp_config.unlink }

    it 'works with real configuration' do
      result = use_case.execute(deploy_labels: deploy_labels, target_environment: 'develop')

      expect(result).to be_success
      expect(result.deployment_targets).not_to be_empty
    end
  end
end
