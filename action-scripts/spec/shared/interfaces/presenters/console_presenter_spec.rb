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

  it 'accepts only the dispatch result fields' do
    expect(described_class.instance_method(:present_label_dispatch_result).parameters.map(&:last)).to eq(%i[deploy_labels labels_added labels_removed changed_files])
  end
  it 'shows each stack identity with all paths generic attributes and exclusion conditions' do
    config = Entities::WorkflowConfig.new('stacks' => [
      { 'name' => 'terragrunt', 'id' => 'aws', 'paths' => ['dystopia/{service}/aws', 'system-components/{service}/aws'], 'environments' => { 'develop' => { 'token' => nil } }, 'exclude' => [{ 'service' => 'demo' }] },
      { 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => { 'repository' => 'registry.example.com' } }
    ])
    expect { described_class.new.present_config_details(config: config) }.to output(/Stack 'aws'.*dystopia.*system-components.*develop.*token.*exclude.*demo.*Stack 'container'.*repository.*registry.example.com/m).to_stdout
  end

  it 'shows complete diagnostic targets and their exclusion status' do
    target = Entities::DeploymentTarget.new(service: 'demo', stack: 'terragrunt', stack_id: 'aws', working_directory: 'teams/platform/demo/aws', captures: { 'team' => 'platform' }, attributes: { 'token' => nil })
    expect do
      described_class.new.present_service_test_result(service_name: 'demo', matches: [{ target: target, excluded: true }])
    end.to output(/stack_id: "aws".*working_directory: "teams\/platform\/demo\/aws".*token: nil.*team: "platform".*excluded: true/m).to_stdout
  end

end
