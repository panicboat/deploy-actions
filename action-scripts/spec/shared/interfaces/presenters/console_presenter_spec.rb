require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe Interfaces::Presenters::ConsolePresenter do
  it 'displays labels and changed files without service exclusion metadata' do
    expect do
      described_class.new.present_label_dispatch_result(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: [], changed_files: ['dystopia/demo/main.rb'])
    end.to output(/Deploy Labels: deploy:demo.*Changed Files: 1 files/m).to_stdout
  end

  it 'displays console results when loaded in a GitHub Actions process' do
    loader = File.expand_path('../../../../shared/shared_loader', __dir__)
    script = "Interfaces::Presenters::ConsolePresenter.new.present_label_dispatch_result(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: [], changed_files: ['dystopia/demo/main.rb'])"
    stdout, stderr, status = Open3.capture3({ 'GITHUB_ACTIONS' => 'true' }, RbConfig.ruby, '-r', loader, '-e', script)

    expect(status).to be_success, stderr
    expect(stdout).to include('Deploy Labels: deploy:demo', 'Changed Files: 1 files')
  end

  it 'does not exit on errors' do
    expect { described_class.new.present_error('boom') }.to output(/Error: boom/).to_stdout
  end

  it 'colors the heading of the shared text' do
    expect do
      described_class.new.present_label_dispatch_result(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: [])
    end.to output("#{'🏷️  Label Dispatch Results'.colorize(:blue)}\nDeploy Labels: \nChanged Files: 0 files\n").to_stdout
  end

  it 'accepts only the dispatch result fields' do
    expect(described_class.instance_method(:present_label_dispatch_result).parameters.map(&:last)).to eq(%i[deploy_labels labels_added labels_removed changed_files])
  end

  it 'accepts only the matrix fields' do
    expect(described_class.instance_method(:present_deployment_matrix).parameters.map(&:last)).to eq(%i[deployment_targets deploy_labels target_environments pr_number])
  end

  it 'colors the heading of the service targets text' do
    stack = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws' }] }]).stacks.first
    candidate = Entities::TargetCandidate.new(stack: stack, service: 'demo', environment: nil, root: 'demo', working_directory: 'demo/aws', captures: {})
    lines = Interfaces::Presenters::TextFormat.service_targets(service: 'demo', target_environments: [], candidates: [candidate])
    expect do
      described_class.new.present_service_targets(service: 'demo', target_environments: [], candidates: [candidate])
    end.to output("#{lines.first.colorize(:green)}\n#{lines.drop(1).map { |line| "#{line}\n" }.join}").to_stdout
  end

  it 'accepts only the service target fields' do
    expect(described_class.instance_method(:present_service_targets).parameters.map(&:last)).to eq(%i[service target_environments candidates])
  end

  it 'colors the validation heading by the result' do
    expect { described_class.new.present_config_validation_result(valid: true, summary: 'ok') }.to output("#{'✅ Configuration is valid'.colorize(:green)}\nSummary:\nok\n").to_stdout
    expect { described_class.new.present_config_validation_result(valid: false, errors: ['boom']) }.to output("#{'❌ Configuration validation failed'.colorize(:red)}\n  - boom\n").to_stdout
  end

  it 'accepts only the validation fields' do
    expect(described_class.instance_method(:present_config_validation_result).parameters.map(&:last)).to eq(%i[valid errors summary])
  end

  it 'does not present service discovery results' do
    expect(described_class.new).not_to respond_to(:present_service_discovery_result)
  end

  it 'shows complete diagnostic targets and their exclusion status' do
    stack = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws', 'attributes' => { 'token' => nil }, 'exclude' => [{ 'team' => 'platform' }] }] }]).stacks.first
    candidate = Entities::TargetCandidate.new(stack: stack, service: 'demo', environment: nil, root: 'teams/platform/demo', working_directory: 'teams/platform/demo/aws', captures: { 'team' => 'platform' })
    expect do
      described_class.new.present_service_test_result(service_name: 'demo', candidates: [candidate])
    end.to output(/stack: "aws".*working_directory: "teams\/platform\/demo\/aws".*token: nil.*team: "platform".*excluded: true/m).to_stdout
  end

end
