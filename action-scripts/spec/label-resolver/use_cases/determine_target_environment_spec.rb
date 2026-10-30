require 'spec_helper'

RSpec.describe UseCases::LabelResolver::DetermineTargetEnvironment do
  let(:config) { build(:workflow_config) }
  let(:client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:resolve_environments) { UseCases::Shared::ResolveEnvironments.new(directory_scanner: Infrastructure::DirectoryScanner.new(repository_root: Dir.pwd)) }
  subject(:use_case) { described_class.new(config_client: client, resolve_environments: resolve_environments) }

  it 'returns the environments resolved from the loaded configuration' do
    expect(use_case.execute(target_environments: %w[production production]).value).to eq(['production'])
  end

  it 'returns the failure for unknown environment names' do
    expect(use_case.execute(target_environments: ['preview']).error_message).to eq('Target environments not found in configuration: preview')
  end

  it 'propagates configuration errors as failures' do
    allow(client).to receive(:load_workflow_config).and_raise('invalid configuration')
    expect(use_case.execute(target_environments: []).error_message).to eq('Failed to determine target environments: invalid configuration')
  end
end
