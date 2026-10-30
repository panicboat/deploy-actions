require 'spec_helper'
require 'tmpdir'

RSpec.describe Interfaces::Presenters::GitHubActionsPresenter do
  around do |example|
    Dir.mktmpdir do |root|
      @output_path = File.join(root, 'GITHUB_OUTPUT')
      File.write(@output_path, '')
      example.run
    end
  end

  subject(:presenter) { described_class.new(output_path: @output_path) }

  def dispatch(presenter)
    presenter.present_label_dispatch_result(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: ['deploy:old'], changed_files: ['dystopia/demo/main.rb'])
  end

  it 'writes public dispatch outputs without global service exclusion fields' do
    expect { dispatch(presenter) }.to output.to_stdout
    expect(File.read(@output_path).lines.map(&:strip)).to contain_exactly('labels-added=["deploy:demo"]', 'labels-removed=["deploy:old"]', 'services-detected=["demo"]', 'has-changes=true')
  end

  it 'writes false and empty outputs when no labels are detected' do
    expect { presenter.present_label_dispatch_result(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: []) }.to output.to_stdout
    expect(File.read(@output_path).lines.map(&:strip)).to contain_exactly('labels-added=[]', 'labels-removed=[]', 'services-detected=[]', 'has-changes=false')
  end

  it 'writes the matrix outputs' do
    target = Entities::DeploymentTarget.new(service: 'demo', environment: 'develop', stack: 'aws', working_directory: 'demo/aws')
    expect { presenter.present_deployment_matrix(deployment_targets: [target], deploy_labels: [], target_environments: ['develop'], safety_status: 'passed') }.to output.to_stdout
    expect(File.read(@output_path).lines.map(&:strip)).to contain_exactly('targets=[{"service":"demo","environment":"develop","stack":"aws","working_directory":"demo/aws"}]', 'has-targets=true', 'safety-status=passed')
  end

  it 'prints the shared text without color' do
    expect { dispatch(presenter) }.to output(Interfaces::Presenters::TextFormat.label_dispatch(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: ['deploy:old'], changed_files: ['dystopia/demo/main.rb']).map { |line| "#{line}\n" }.join).to_stdout
  end

  it 'does not exit on errors' do
    expect { presenter.present_error('boom') }.to output("::error::boom\n").to_stdout
  end

  it 'raises when GITHUB_OUTPUT is not set' do
    expect { dispatch(described_class.new(output_path: nil)) }.to raise_error(RuntimeError, 'GITHUB_OUTPUT is not set')
  end

  it 'does not write GITHUB_ENV' do
    env_path = File.join(File.dirname(@output_path), 'GITHUB_ENV')
    File.write(env_path, '')
    original = ENV['GITHUB_ENV']
    ENV['GITHUB_ENV'] = env_path
    expect { dispatch(presenter) }.to output.to_stdout
    expect { presenter.present_error('boom') }.to output.to_stdout
    expect(File.read(env_path)).to eq('')
  ensure
    ENV['GITHUB_ENV'] = original
  end

  it 'does not print the legacy set-output command' do
    expect { dispatch(presenter) }.not_to output(/::set-output/).to_stdout
  end

  it 'accepts only the dispatch result fields' do
    expect(described_class.instance_method(:present_label_dispatch_result).parameters.map(&:last)).to eq(%i[deploy_labels labels_added labels_removed changed_files])
  end
  describe '#present_config_details' do
    let(:config) do
      Entities::WorkflowConfigParser.parse(
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
      presenter.present_config_details(config: config)
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
      presenter.present_service_test_result(service_name: 'demo', matches: [{ target: target, excluded: true }])
    end.to output(/stack: "aws".*working_directory: "teams\/platform\/demo\/aws".*token: nil.*team: "platform".*excluded: true/m).to_stdout
  end

end
