require 'spec_helper'

RSpec.describe UseCases::LabelManagement::DispatchLabels do
  let(:github_client) { instance_double(Infrastructure::GitHubClient, get_pr_info: { base_sha: 'base123', head_sha: 'head456' }) }
  let(:detection) { UseCases::LabelManagement::Detection.new(deploy_labels: [Entities::DeployLabel.new('deploy:api')], changed_files: ['apps/api/main.rb']) }
  let(:detect_changed_services) { instance_double(UseCases::LabelManagement::DetectChangedServices, execute: Entities::Result.success(detection)) }
  let(:label_sync) { UseCases::LabelManagement::LabelSync.new(labels_added: ['deploy:api'], labels_removed: ['deploy:old']) }
  let(:manage_labels) { instance_double(UseCases::LabelManagement::ManageLabels, execute: Entities::Result.success(label_sync)) }
  subject(:use_case) { described_class.new(github_client: github_client, detect_changed_services: detect_changed_services, manage_labels: manage_labels) }

  it 'detects changes between the pull request SHAs' do
    use_case.execute(pr_number: 12)
    expect(github_client).to have_received(:get_pr_info).with(12)
    expect(detect_changed_services).to have_received(:execute).with(base_ref: 'base123', head_ref: 'head456')
  end

  it 'syncs the detected labels and returns the dispatch' do
    result = use_case.execute(pr_number: 12)
    expect(manage_labels).to have_received(:execute).with(pr_number: 12, required_labels: ['deploy:api'])
    expect(result.value).to eq(UseCases::LabelManagement::Dispatch.new(detection: detection, labels_added: ['deploy:api'], labels_removed: ['deploy:old']))
  end

  it 'syncs labels even when no services are detected' do
    allow(detect_changed_services).to receive(:execute).and_return(Entities::Result.success(UseCases::LabelManagement::Detection.new(deploy_labels: [], changed_files: [])))
    expect(use_case.execute(pr_number: 12)).to be_success
    expect(manage_labels).to have_received(:execute).with(pr_number: 12, required_labels: [])
  end

  it 'stops when the pull request cannot be read' do
    allow(github_client).to receive(:get_pr_info).and_raise(StandardError, 'not found')
    result = use_case.execute(pr_number: 12)
    expect(result.error_message).to eq('Failed to get PR info: not found')
    expect(detect_changed_services).not_to have_received(:execute)
    expect(manage_labels).not_to have_received(:execute)
  end

  it 'stops before syncing labels when detection fails' do
    allow(detect_changed_services).to receive(:execute).and_return(Entities::Result.failure('git diff failed'))
    expect(use_case.execute(pr_number: 12).error_message).to eq('git diff failed')
    expect(manage_labels).not_to have_received(:execute)
  end

  it 'returns the label sync failure' do
    allow(manage_labels).to receive(:execute).and_return(Entities::Result.failure('Failed to add label deploy:api'))
    expect(use_case.execute(pr_number: 12).error_message).to eq('Failed to add label deploy:api')
  end
end
