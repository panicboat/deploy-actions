require 'spec_helper'

RSpec.describe UseCases::LabelManagement::DetectChangedServices do
  let(:config_hash) { { 'services' => [{ 'id' => 'app', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'terragrunt', 'path' => 'aws/{environment}' }] }] } }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: Entities::WorkflowConfigParser.parse(config_hash)) }
  let(:changed_files) { ['teams/platform/demo/aws/develop/main.tf'] }
  let(:git_client) { instance_double(Infrastructure::GitClient, changed_files: changed_files) }
  subject(:use_case) { described_class.new(config_client: config_client, git_client: git_client) }

  it 'returns failures for git errors' do
    allow(git_client).to receive(:changed_files).and_raise('git error')
    expect(use_case.execute.error_message).to include('git error')
  end

  it 'builds labels with the configured prefix' do
    config_hash['labels'] = { 'prefix' => 'release/' }
    result = use_case.execute(base_ref: 'base', head_ref: 'head')
    expect(result.value).to be_a(UseCases::LabelManagement::Detection)
    expect(result.value.deploy_labels.map(&:to_s)).to eq(['release/demo'])
    expect(result.value.changed_files).to eq(changed_files)
    expect(git_client).to have_received(:changed_files).with(base_ref: 'base', head_ref: 'head')
  end
end
