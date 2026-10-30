require 'spec_helper'

RSpec.describe Interfaces::Presenters::TextFormat do
  describe '.label_dispatch' do
    it 'lists the labels, the label changes, and the changed files' do
      lines = described_class.label_dispatch(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: ['deploy:old'], changed_files: ['dystopia/demo/main.rb'])
      expect(lines).to eq(['🏷️  Label Dispatch Results', 'Deploy Labels: deploy:demo', 'Labels Added: deploy:demo', 'Labels Removed: deploy:old', 'Changed Files: 1 files', '  - dystopia/demo/main.rb'])
    end

    it 'omits empty label changes' do
      lines = described_class.label_dispatch(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: [])
      expect(lines).to eq(['🏷️  Label Dispatch Results', 'Deploy Labels: ', 'Changed Files: 0 files'])
    end

    it 'shows only the first ten changed files' do
      lines = described_class.label_dispatch(deploy_labels: [], labels_added: [], labels_removed: [], changed_files: (1..12).map { |index| "file#{index}" })
      expect(lines.drop(2)).to eq(['Changed Files: 12 files', '  (showing first 10 files)', *(1..10).map { |index| "  - file#{index}" }, '  ... and 2 more files'])
    end
  end

  describe '.deployment_matrix' do
    it 'shows the context and the targets grouped by environment with their attributes' do
      target = Entities::DeploymentTarget.new(service: 'demo', environment: 'develop', stack: 'aws', working_directory: 'demo/aws', attributes: { 'type' => 'terragrunt' })
      lines = described_class.deployment_matrix(deployment_targets: [target], deploy_labels: [Entities::DeployLabel.new('deploy:demo')], target_environments: %w[develop production], pr_number: 12)
      expect(lines).to eq(['🚀 Deployment Matrix', 'Target Environments: develop, production', 'PR Number: #12', '', 'Deploy Labels: deploy:demo', 'Deployment Targets: 1', '', '  Environment: develop', '    demo:aws -> demo/aws', '      type: terragrunt', ''])
    end

    it 'names a single target environment' do
      expect(described_class.deployment_matrix(deployment_targets: [], deploy_labels: [], target_environments: ['develop'])).to include('Target Environment: develop')
    end

    it 'accepts only the matrix fields' do
      expect(described_class.method(:deployment_matrix).parameters.map(&:last)).to eq(%i[deployment_targets deploy_labels target_environments pr_number])
    end
  end

  describe '.config_validation' do
    it 'shows the summary of a valid configuration' do
      lines = described_class.config_validation(valid: true, errors: [], summary: "Configuration validation successful\nservices: 1 configured")
      expect(lines).to eq(['✅ Configuration is valid', 'Summary:', "Configuration validation successful\nservices: 1 configured"])
    end

    it 'lists the errors of an invalid configuration' do
      lines = described_class.config_validation(valid: false, errors: ['first', 'second'], summary: nil)
      expect(lines).to eq(['❌ Configuration validation failed', '  - first', '  - second'])
    end
  end

  describe '.service_test_result' do
    it 'shows every matrix field of each target and its exclusion status' do
      stack = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws' }] }]).stacks.first
      candidate = Entities::TargetCandidate.new(stack: stack, service: 'demo', environment: nil, working_directory: 'demo/aws', captures: {}).to_listed_target
      lines = described_class.service_test_result(service_name: 'demo', candidates: [candidate])
      expect(lines).to eq(['Service Configuration Test', 'Service: demo', 'Target:', '  service: "demo"', '  environment: nil', '  stack: "aws"', '  working_directory: "demo/aws"', '  excluded: false'])
    end
  end

  describe '.service_targets' do
    let(:config) do
      Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [
        { 'id' => 'kustomize', 'path' => 'overlays/{environment}', 'exclude' => [{ 'environment' => 'production' }] },
        { 'id' => 'container', 'path' => '.' }
      ] }])
    end
    let(:targets) do
      [
        Entities::TargetCandidate.new(stack: config.stacks[0], service: 'demo', environment: 'develop', working_directory: 'demo/overlays/develop', captures: {}),
        Entities::TargetCandidate.new(stack: config.stacks[1], service: 'demo', environment: nil, working_directory: 'demo', captures: {})
      ].map(&:to_deployment_target)
    end

    it 'shows the service, the environments, and each target' do
      lines = described_class.service_targets(service: 'demo', target_environments: %w[develop production], targets: targets)
      expect(lines).to eq([
        '🎯 Service Targets', 'Service: demo', 'Target Environments: develop, production', 'Targets: 2',
        '', '  demo:kustomize (develop) -> demo/overlays/develop',
        '', '  demo:container -> demo'
      ])
    end

    it 'names a single target environment and omits the line when none is requested' do
      expect(described_class.service_targets(service: 'demo', target_environments: ['develop'], targets: [])).to include('Target Environment: develop')
      expect(described_class.service_targets(service: 'demo', target_environments: [], targets: [])).to eq(['🎯 Service Targets', 'Service: demo', 'Targets: 0'])
    end
  end
end
