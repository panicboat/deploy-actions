require 'spec_helper'

RSpec.describe UseCases::LabelManagement::ManageLabels do
  let(:config) { Entities::WorkflowConfig.new('labels' => { 'prefix' => 'release/', 'extra_prefixes' => ['manual/'] }, 'stacks' => [{ 'name' => 'container', 'paths' => ['{service}'], 'attributes' => {} }]) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:github_client) { instance_double(Infrastructure::GitHubClient, remove_label_from_pr: nil, ensure_label_exists: nil, add_label_to_pr: nil) }
  subject(:use_case) { described_class.new(github_client: github_client, config_client: config_client) }

  it 'replaces only labels with the configured prefix' do
    allow(github_client).to receive(:get_deploy_labels).and_return(['release/old'], [])
    result = use_case.execute(pr_number: 1, required_labels: ['release/api'])
    expect(result).to be_success
    expect(github_client).to have_received(:get_deploy_labels).with(1, prefix: 'release/').twice
    expect(github_client).to have_received(:remove_label_from_pr).with(1, 'release/old')
    expect(github_client).not_to have_received(:remove_label_from_pr).with(1, start_with('manual/'))
    expect(github_client).to have_received(:add_label_to_pr).with(1, 'release/api')
  end
end
