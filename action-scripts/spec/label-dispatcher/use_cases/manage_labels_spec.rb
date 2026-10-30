require 'spec_helper'

RSpec.describe UseCases::LabelManagement::ManageLabels do
  let(:config) { Entities::WorkflowConfigParser.parse('labels' => { 'prefix' => 'release/', 'extra_prefixes' => ['manual/'] }, 'services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }]) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:github_client) { instance_double(Infrastructure::GitHubClient, remove_label_from_pr: nil, ensure_label_exists: nil, add_label_to_pr: nil) }
  subject(:use_case) { described_class.new(github_client: github_client, config_client: config_client) }

  it 'replaces only labels with the configured prefix' do
    allow(github_client).to receive(:get_deploy_labels).and_return(['release/old'])
    result = use_case.execute(pr_number: 1, required_labels: ['release/api'])
    expect(result).to be_success
    expect(github_client).to have_received(:get_deploy_labels).with(1, prefix: 'release/').once
    expect(github_client).to have_received(:remove_label_from_pr).with(1, 'release/old')
    expect(github_client).not_to have_received(:remove_label_from_pr).with(1, start_with('manual/'))
    expect(github_client).to have_received(:add_label_to_pr).with(1, 'release/api')
  end

  it 'reports the difference between the previous and the required labels' do
    allow(github_client).to receive(:get_deploy_labels).and_return(['release/old', 'release/api'], [])
    result = use_case.execute(pr_number: 1, required_labels: ['release/api', 'release/web'])
    expect(result.value).to eq(UseCases::LabelManagement::LabelSync.new(labels_added: ['release/web'], labels_removed: ['release/old']))
  end

  it 're-adds labels that stay so each push fires the labeled event' do
    allow(github_client).to receive(:get_deploy_labels).and_return(['release/api'], [])
    result = use_case.execute(pr_number: 1, required_labels: ['release/api'])
    expect(result.value).to eq(UseCases::LabelManagement::LabelSync.new(labels_added: [], labels_removed: []))
    expect(github_client).to have_received(:remove_label_from_pr).with(1, 'release/api').ordered
    expect(github_client).to have_received(:add_label_to_pr).with(1, 'release/api').ordered
  end

  it 'returns a failure when the GitHub client raises' do
    allow(github_client).to receive(:get_deploy_labels).and_raise('Failed to get PR labels: boom')
    result = use_case.execute(pr_number: 1, required_labels: ['release/api'])
    expect(result).to be_failure
    expect(result.error_message).to eq('Failed to get PR labels: boom')
  end
end
