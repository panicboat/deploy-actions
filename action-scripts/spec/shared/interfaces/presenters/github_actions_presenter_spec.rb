require 'spec_helper'
require 'tmpdir'

RSpec.describe Interfaces::Presenters::GitHubActionsPresenter do
  around do |example|
    original = ENV.to_h.slice('GITHUB_ENV', 'GITHUB_OUTPUT')
    Dir.mktmpdir do |root|
      %w[GITHUB_ENV GITHUB_OUTPUT].each do |key|
        ENV[key] = File.join(root, key)
        File.write(ENV[key], '')
      end
      example.run
    end
  ensure
    %w[GITHUB_ENV GITHUB_OUTPUT].each { |key| ENV[key] = original[key] }
  end

  it 'writes public dispatch outputs without global service exclusion fields' do
    described_class.new.present_label_dispatch_result(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: ['deploy:old'], changed_files: ['dystopia/demo/main.rb'])
    output = File.read(ENV['GITHUB_OUTPUT'])
    expect(output.lines.map(&:strip)).to contain_exactly('deploy-labels=["deploy:demo"]', 'labels-added=["deploy:demo"]', 'labels-removed=["deploy:old"]', 'services-detected=["demo"]', 'has-changes=true')
    env = File.read(ENV['GITHUB_ENV'])
    expect(env).to include('SERVICES_DETECTED=["demo"]', 'DEPLOY_LABELS=["deploy:demo"]', 'HAS_CHANGES=true')
    expect(env).not_to include('EXCLUDED_SERVICES', 'HAS_EXCLUDED_SERVICES')
  end

  it 'writes false and empty outputs when no labels are detected' do
    described_class.new.present_label_dispatch_result(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: [])
    expect(File.read(ENV['GITHUB_OUTPUT'])).to include('deploy-labels=[]', 'services-detected=[]', 'has-changes=false')
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
