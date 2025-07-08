# spec/deploy-resolver/use_cases/determine_target_environment_spec.rb

require 'spec_helper'

RSpec.describe UseCases::DeployResolver::DetermineTargetEnvironment do
  let(:config_client) { double('ConfigClient') }
  let(:config) { build(:workflow_config) }
  
  subject(:use_case) { described_class.new(config_client: config_client) }

  before do
    allow(config_client).to receive(:load_workflow_config).and_return(config)
  end

  describe '#execute' do
    context 'with mapped branch name' do
      let(:branch_name) { 'develop' }

      before do
        allow(config).to receive(:branch_to_environment).with(branch_name).and_return('develop')
      end

      it 'returns success result with target environment' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_success
        expect(result.target_environment).to eq('develop')
        expect(result.branch_name).to eq(branch_name)
      end
    end

    context 'with unmapped branch name' do
      let(:branch_name) { 'feature/new-feature' }

      before do
        allow(config).to receive(:branch_to_environment).with(branch_name).and_return(nil)
      end

      it 'returns failure result with error message' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('No environment mapping found for branch')
        expect(result.error_message).to include(branch_name)
      end
    end

    context 'with staging branch' do
      let(:branch_name) { 'staging' }

      before do
        allow(config).to receive(:branch_to_environment).with(branch_name).and_return('staging')
      end

      it 'returns staging environment' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_success
        expect(result.target_environment).to eq('staging')
      end
    end

    context 'with production branch' do
      let(:branch_name) { 'production' }

      before do
        allow(config).to receive(:branch_to_environment).with(branch_name).and_return('production')
      end

      it 'returns production environment' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_success
        expect(result.target_environment).to eq('production')
      end
    end

    context 'with nil branch name' do
      let(:branch_name) { nil }

      it 'returns failure result' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('Branch name is required')
      end
    end

    context 'with empty branch name' do
      let(:branch_name) { '' }

      it 'returns failure result' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('Branch name is required')
      end
    end

    context 'when config loading fails' do
      let(:branch_name) { 'develop' }
      let(:error) { StandardError.new('Config file not found') }

      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
      end

      it 'handles error and returns failure result' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('Failed to load configuration')
        expect(result.error_message).to include('Config file not found')
      end
    end

    context 'with complex branch patterns' do
      let(:branch_patterns) do
        {
          'main' => 'production',
          'master' => 'production',
          'develop' => 'develop',
          'dev' => 'develop',
          'staging' => 'staging',
          'release/*' => 'staging'
        }
      end

      before do
        allow(config).to receive_message_chain(:raw_config, :[]).with('branch_patterns').and_return(branch_patterns)
      end

      context 'with main branch' do
        let(:branch_name) { 'main' }

        before do
          allow(config).to receive(:branch_to_environment).with(branch_name).and_return('production')
        end

        it 'maps to production environment' do
          result = use_case.execute(branch_name: branch_name)

          expect(result).to be_success
          expect(result.target_environment).to eq('production')
        end
      end

      context 'with alternative develop branch name' do
        let(:branch_name) { 'dev' }

        before do
          allow(config).to receive(:branch_to_environment).with(branch_name).and_return('develop')
        end

        it 'maps to develop environment' do
          result = use_case.execute(branch_name: branch_name)

          expect(result).to be_success
          expect(result.target_environment).to eq('develop')
        end
      end
    end

    context 'integration with real configuration' do
      let(:real_config_client) { Infrastructure::ConfigClient.new }
      let(:use_case) { described_class.new(config_client: real_config_client) }
      let(:temp_config) { create_test_config(default_test_config) }

      after { temp_config.unlink }

      it 'works with real configuration' do
        result = use_case.execute(branch_name: 'develop')

        expect(result).to be_success
        expect(result.target_environment).to eq('develop')
      end
    end
  end

  describe 'error handling edge cases' do
    let(:branch_name) { 'develop' }

    context 'when config returns unexpected nil' do
      before do
        allow(config).to receive(:branch_to_environment).and_return(nil)
      end

      it 'handles nil mapping gracefully' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('No environment mapping found')
      end
    end

    context 'when config method raises exception' do
      let(:error) { StandardError.new('Configuration method error') }

      before do
        allow(config).to receive(:branch_to_environment).and_raise(error)
      end

      it 'handles configuration method errors' do
        result = use_case.execute(branch_name: branch_name)

        expect(result).to be_failure
        expect(result.error_message).to include('Failed to determine target environment')
        expect(result.error_message).to include('Configuration method error')
      end
    end
  end
end