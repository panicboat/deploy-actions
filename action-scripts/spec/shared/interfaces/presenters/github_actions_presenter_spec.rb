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
  describe '#present_config_details' do
    let(:config) do
      Entities::WorkflowConfig.new(
        'profiles' => { 'aws-develop' => { 'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan' } },
        'services' => [
          { 'id' => 'app', 'roots' => ['dystopia/{service}', 'system-components/{service}'], 'ignore' => ['**/README.md'], 'stacks' => [
            { 'id' => 'aws', 'path' => 'aws', 'attributes' => { 'type' => 'terragrunt' }, 'environments' => { 'develop' => { 'use' => ['aws-develop'], 'token' => nil } }, 'exclude' => [{ 'service' => 'demo' }] },
            { 'id' => 'container', 'path' => '.', 'attributes' => { 'repository' => 'registry.example.com' } }
          ] },
          { 'id' => 'tools', 'roots' => ['tools/{service}'], 'stacks' => [{ 'id' => 'scripts', 'path' => '.' }] }
        ]
      )
    end
    let(:printed) do
      original = $stdout
      $stdout = StringIO.new
      described_class.new.present_config_details(config: config)
      $stdout.string
    ensure
      $stdout = original
    end

    def stack_section(id)
      printed[/^  Stack '#{id}':\n(.*?)(?=^  Stack |^Service |\z)/m, 1]
    end

    it 'shows each service with its roots and ignore patterns before its stacks' do
      expect(printed).to include("Service 'app':\n  roots: dystopia/{service}, system-components/{service}\n  ignore: **/README.md\n  Stack 'aws':")
    end

    it 'omits the ignore line for a service without ignore patterns' do
      expect(printed).to include("Service 'tools':\n  roots: tools/{service}\n  Stack 'scripts':")
    end

    it 'shows a dot path as a dot' do
      expect(stack_section('container')).to include("    path: .\n")
      expect(printed).not_to include("path: ''")
    end

    it 'shows the execution path of every root, the exclusion conditions, and the resolved environment attributes under the stack declaring them' do
      expect(stack_section('aws')).to include('dystopia/{service}/aws', 'system-components/{service}/aws', 'type: terragrunt', 'develop', 'iam_role_plan: arn:aws:iam::123456789012:role/plan', 'token', 'exclude', 'service: demo')
    end

    it 'does not show one stack\'s attributes under another stack' do
      expect(stack_section('container')).to include('repository: registry.example.com')
      expect(stack_section('container')).not_to include('terragrunt', 'token', 'demo')
      expect(stack_section('aws')).not_to include('repository')
    end
  end

  it 'shows complete diagnostic targets and their exclusion status' do
    target = Entities::DeploymentTarget.new(service: 'demo', stack: 'aws', working_directory: 'teams/platform/demo/aws', captures: { 'team' => 'platform' }, attributes: { 'token' => nil })
    expect do
      described_class.new.present_service_test_result(service_name: 'demo', matches: [{ target: target, excluded: true }])
    end.to output(/stack: "aws".*working_directory: "teams\/platform\/demo\/aws".*token: nil.*team: "platform".*excluded: true/m).to_stdout
  end

end
