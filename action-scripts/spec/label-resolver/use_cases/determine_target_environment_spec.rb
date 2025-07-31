# spec/label-resolver/use_cases/determine_target_environment_spec.rb

require 'spec_helper'

RSpec.describe UseCases::LabelResolver::DetermineTargetEnvironment do
  let(:config_client) { double('ConfigClient') }
  let(:config) { build(:workflow_config) }

  subject(:use_case) { described_class.new(config_client: config_client) }

  before do
    allow(config_client).to receive(:load_workflow_config).and_return(config)
  end

  describe '#execute' do
    context 'with valid target environments' do
      let(:target_environments) { ['develop'] }

      before do
        allow(config).to receive(:environments).and_return({ 'develop' => { 'environment' => 'develop' } })
        allow(config).to receive(:environment_config).with('develop').and_return({ 'environment' => 'develop' })
      end

      it 'returns success result with target environments' do
        result = use_case.execute(target_environments: target_environments)

        expect(result).to be_success
        expect(result.target_environments).to eq(['develop'])
        expect(result.environment_configs).to eq({ 'develop' => { 'environment' => 'develop' } })
      end
    end

    context 'with multiple environments' do
      let(:target_environments) { ['develop', 'staging'] }

      before do
        allow(config).to receive(:environments).and_return({ 
          'develop' => { 'environment' => 'develop' }, 
          'staging' => { 'environment' => 'staging' } 
        })
        allow(config).to receive(:environment_config).with('develop').and_return({ 'environment' => 'develop' })
        allow(config).to receive(:environment_config).with('staging').and_return({ 'environment' => 'staging' })
      end

      it 'returns success result with multiple environments' do
        result = use_case.execute(target_environments: target_environments)

        expect(result).to be_success
        expect(result.target_environments).to eq(['develop', 'staging'])
        expect(result.environment_configs).to eq({ 
          'develop' => { 'environment' => 'develop' },
          'staging' => { 'environment' => 'staging' } 
        })
      end
    end

    context 'with production environment' do
      let(:target_environments) { ['production'] }

      before do
        allow(config).to receive(:environments).and_return({ 'production' => { 'environment' => 'production' } })
        allow(config).to receive(:environment_config).with('production').and_return({ 'environment' => 'production' })
      end

      it 'returns success result with production environment' do
        result = use_case.execute(target_environments: target_environments)

        expect(result).to be_success
        expect(result.target_environments).to eq(['production'])
      end
    end

    context 'with invalid environment' do
      let(:target_environments) { ['invalid'] }

      before do
        allow(config).to receive(:environments).and_return({})
      end

      it 'returns failure result' do
        result = use_case.execute(target_environments: target_environments)

        expect(result).to be_failure
        expect(result.error_message).to include("Target environment 'invalid' not found in configuration")
      end
    end

    context 'when configuration loading fails' do
      let(:target_environments) { ['develop'] }

      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(StandardError.new('Config error'))
      end

      it 'returns failure result' do
        result = use_case.execute(target_environments: target_environments)

        expect(result).to be_failure
        expect(result.error_message).to include('Failed to determine target environments: Config error')
      end
    end
  end
end