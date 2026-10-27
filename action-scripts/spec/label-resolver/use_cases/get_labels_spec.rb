require 'spec_helper'

RSpec.describe UseCases::LabelResolver::GetLabels do
  let(:config) { Entities::WorkflowConfig.new('labels' => { 'prefix' => 'release/', 'extra_prefixes' => ['manual:'] }, 'stacks' => [{ 'name' => 'container', 'paths' => ['{service}'], 'attributes' => {} }]) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:github_client) { instance_double(Infrastructure::GitHubClient) }
  subject(:use_case) { described_class.new(github_client: github_client, config_client: config_client) }

  it 'reads labels with the prefix and every extra prefix' do
    allow(github_client).to receive(:get_pr_info).with(1).and_return(labels: ['release/api', 'manual:web', 'deploy:db', 'enhancement', 'manual:a/b'])
    result = use_case.execute(pr_number: 1)
    expect(result).to be_success
    expect(result.deploy_labels.map(&:to_s)).to eq(['release/api', 'manual:web'])
    expect(result.raw_labels).to eq(['release/api', 'manual:web', 'manual:a/b'])
  end
end
