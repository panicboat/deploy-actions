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
      lines = described_class.deployment_matrix(deployment_targets: [target], deploy_labels: [Entities::DeployLabel.new('deploy:demo')], target_environments: %w[develop production], pr_number: 12, safety_status: 'passed')
      expect(lines).to eq(['🚀 Deployment Matrix', 'Target Environments: develop, production', 'PR Number: #12', 'Safety Status: passed', '', 'Deploy Labels: deploy:demo', 'Deployment Targets: 1', '', '  Environment: develop', '    demo:aws -> demo/aws', '      type: terragrunt', ''])
    end

    it 'names a single target environment' do
      expect(described_class.deployment_matrix(deployment_targets: [], deploy_labels: [], target_environment: 'develop')).to include('Target Environment: develop')
      expect(described_class.deployment_matrix(deployment_targets: [], deploy_labels: [], target_environments: ['develop'])).to include('Target Environment: develop')
    end
  end

  describe '.config_details' do
    it 'shows each service with its roots and the YAML of its stacks' do
      config = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'tools', 'roots' => ['tools/{service}'], 'stacks' => [{ 'id' => 'scripts', 'path' => '.' }] }])
      expect(described_class.config_details(config: config).join("\n")).to eq("Workflow Configuration\nEnvironments: \nService 'tools':\n  roots: tools/{service}\n  Stack 'scripts':\n    path: .\n    paths:\n    - tools/{service}\n    attributes: {}\n    exclude: []")
    end
  end

  describe '.service_test_result' do
    it 'shows every matrix field of each target and its exclusion status' do
      target = Entities::DeploymentTarget.new(service: 'demo', stack: 'aws', working_directory: 'demo/aws')
      lines = described_class.service_test_result(service_name: 'demo', matches: [{ target: target, excluded: false }])
      expect(lines.first(3)).to eq(['Service Configuration Test', 'Service: demo', 'Target:'])
      expect(lines).to include('  service: "demo"', '  working_directory: "demo/aws"', '  excluded: false')
    end
  end
end
