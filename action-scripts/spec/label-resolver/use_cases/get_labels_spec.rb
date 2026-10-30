require 'spec_helper'

RSpec.describe UseCases::LabelResolver::GetLabels do
  let(:config) { Entities::WorkflowConfigParser.parse('labels' => { 'prefix' => 'release/', 'extra_prefixes' => ['manual:'] }, 'services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }]) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:github_client) { instance_double(Infrastructure::GitHubClient) }
  subject(:use_case) { described_class.new(github_client: github_client, config_client: config_client) }

  it 'reads labels with the prefix and every extra prefix' do
    allow(github_client).to receive(:get_pr_info).with(1).and_return(labels: ['release/api', 'manual:web', 'deploy:db', 'enhancement', 'manual:a/b'])
    result = use_case.execute(pr_number: 1)
    expect(result).to be_success
    expect(result.value.map(&:to_s)).to eq(['release/api', 'manual:web'])
  end

  it 'prefixes errors from reading the pull request' do
    allow(github_client).to receive(:get_pr_info).and_raise(StandardError, 'Not Found')
    expect(use_case.execute(pr_number: 1).error_message).to eq('Failed to retrieve PR labels: Not Found')
  end
end
