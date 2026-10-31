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

  it 'writes no outputs for a dispatch result' do
    expect { dispatch(presenter) }.to output.to_stdout
    expect(File.read(@output_path)).to eq('')
  end

  it 'writes no outputs when no labels are detected' do
    expect { presenter.present_label_dispatch_result(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: []) }.to output.to_stdout
    expect(File.read(@output_path)).to eq('')
  end

  it 'writes the matrix outputs' do
    target = Entities::DeploymentTarget.new(service: 'demo', environment: 'develop', stack: 'aws', working_directory: 'demo/aws')
    expect { presenter.present_deployment_matrix(deployment_targets: [target], deploy_labels: [], target_environments: ['develop'], pr_number: 12) }.to output.to_stdout
    expect(File.read(@output_path).lines.map(&:strip)).to contain_exactly('targets=[{"service":"demo","environment":"develop","stack":"aws","working_directory":"demo/aws"}]', 'has-targets=true')
  end

  it 'writes false and an empty matrix when no targets are resolved' do
    expect { presenter.present_deployment_matrix(deployment_targets: [], deploy_labels: [], target_environments: [], pr_number: 12) }.to output.to_stdout
    expect(File.read(@output_path).lines.map(&:strip)).to contain_exactly('targets=[]', 'has-targets=false')
  end

  it 'accepts only the matrix fields' do
    expect(described_class.instance_method(:present_deployment_matrix).parameters.map(&:last)).to eq(%i[deployment_targets deploy_labels target_environments pr_number])
  end

  describe '#present_service_targets' do
    let(:stack_config) do
      Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [
        { 'id' => 'aws', 'path' => 'aws' },
        { 'id' => 'alb', 'path' => 'alb', 'exclude' => [{ 'service' => 'demo' }] }
      ] }])
    end
    let(:target) { Entities::TargetCandidate.new(stack: stack_config.stacks[0], service: 'demo', environment: nil, working_directory: 'demo/aws', captures: {}).to_deployment_target }
    let(:excluded_target) { Entities::TargetCandidate.new(stack: stack_config.stacks[1], service: 'demo', environment: nil, working_directory: 'aws/alb/alb', captures: {}).to_deployment_target }
    let(:target_item) { '{"service":"demo","environment":null,"stack":"aws","working_directory":"demo/aws"}' }
    let(:excluded_item) { '{"service":"demo","environment":null,"stack":"alb","working_directory":"aws/alb/alb"}' }

    it 'writes only the given targets and their presence' do
      expect { presenter.present_service_targets(service: 'demo', target_environments: [], targets: [target]) }.to output.to_stdout
      expect(File.read(@output_path).lines.map(&:strip)).to eq(["targets=[#{target_item}]", 'has-targets=true'])
    end

    it 'does not filter the given targets by exclusion' do
      expect { presenter.present_service_targets(service: 'demo', target_environments: [], targets: [excluded_target]) }.to output.to_stdout
      expect(File.read(@output_path).lines.map(&:strip)).to eq(["targets=[#{excluded_item}]", 'has-targets=true'])
    end

    it 'writes empty outputs when no target exists' do
      expect { presenter.present_service_targets(service: 'missing', target_environments: [], targets: []) }.to output.to_stdout
      expect(File.read(@output_path).lines.map(&:strip)).to eq(['targets=[]', 'has-targets=false'])
    end

    it 'prints the shared text without color' do
      expected = Interfaces::Presenters::TextFormat.service_targets(service: 'demo', target_environments: [], targets: [target]).map { |line| "#{line}\n" }.join
      expect { presenter.present_service_targets(service: 'demo', target_environments: [], targets: [target]) }.to output(expected).to_stdout
    end

    it 'accepts only the service target fields' do
      expect(described_class.instance_method(:present_service_targets).parameters.map(&:last)).to eq(%i[service target_environments targets])
    end

    it 'raises when GITHUB_OUTPUT is not set' do
      expect { described_class.new(output_path: nil).present_service_targets(service: 'demo', target_environments: [], targets: []) }.to raise_error(RuntimeError, 'GITHUB_OUTPUT is not set')
    end
  end

  it 'prints the shared text without color' do
    expect { dispatch(presenter) }.to output(Interfaces::Presenters::TextFormat.label_dispatch(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: ['deploy:old'], changed_files: ['dystopia/demo/main.rb']).map { |line| "#{line}\n" }.join).to_stdout
  end

  it 'does not exit on errors' do
    expect { presenter.present_error('boom') }.to output("::error::boom\n").to_stdout
  end

  it 'presents a dispatch result without an output file' do
    expect { dispatch(described_class.new(output_path: nil)) }.to output(/Label Dispatch Results/).to_stdout
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

  it 'writes no outputs for a validation result' do
    expect { presenter.present_config_validation_result(valid: false, errors: ['boom']) }.to output(/Configuration validation failed/).to_stdout
    expect(File.read(@output_path)).to eq('')
  end

  it 'annotates each validation error after the shared text' do
    expect { presenter.present_config_validation_result(valid: false, errors: ['first', 'second']) }.to output("❌ Configuration validation failed\n  - first\n  - second\n::error::first\n::error::second\n").to_stdout
  end

  it 'prints the shared text of a valid configuration without annotations' do
    expect { presenter.present_config_validation_result(valid: true, summary: 'ok') }.to output("✅ Configuration is valid\nSummary:\nok\n").to_stdout
  end

  it 'accepts only the validation fields' do
    expect(described_class.instance_method(:present_config_validation_result).parameters.map(&:last)).to eq(%i[valid errors summary])
  end

  it 'does not present service discovery results' do
    expect(presenter).not_to respond_to(:present_service_discovery_result)
  end

  it 'shows complete diagnostic targets and their exclusion status' do
    stack = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws', 'attributes' => { 'token' => nil }, 'exclude' => [{ 'team' => 'platform' }] }] }]).stacks.first
    candidate = Entities::TargetCandidate.new(stack: stack, service: 'demo', environment: nil, working_directory: 'teams/platform/demo/aws', captures: { 'team' => 'platform' }).to_listed_target
    expect do
      presenter.present_service_test_result(service_name: 'demo', candidates: [candidate])
    end.to output(/stack: "aws".*working_directory: "teams\/platform\/demo\/aws".*token: nil.*team: "platform".*excluded: true/m).to_stdout
  end

end
