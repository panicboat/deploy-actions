require 'spec_helper'

RSpec.describe Interfaces::Controllers::LabelResolverController do
  let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
  let(:deployment_targets) { [build(:deployment_target)] }
  let(:get_labels) { instance_double(UseCases::LabelResolver::GetLabels) }
  let(:generate_matrix) { instance_double(UseCases::LabelResolver::GenerateMatrix) }
  let(:list_service_targets) { instance_double(UseCases::LabelResolver::ListServiceTargets) }
  let(:presenter) { instance_double(Interfaces::Presenters::ConsolePresenter, present_deployment_matrix: nil, present_service_targets: nil, present_error: nil) }

  subject(:controller) { described_class.new(get_labels: -> { get_labels }, generate_matrix: generate_matrix, list_service_targets: list_service_targets, presenter: presenter) }

  describe '#resolve' do
    before { allow(get_labels).to receive(:execute).with(pr_number: 123).and_return(Entities::Result.success(deploy_labels)) }

    it 'presents the matrix generated for the requested environments' do
      allow(generate_matrix).to receive(:execute).with(deploy_labels: deploy_labels, target_environments: %w[develop staging]).and_return(Entities::Result.success(deployment_targets))

      result = controller.resolve(pr_number: 123, environments: %w[develop staging])

      expect(result.value).to eq(deployment_targets)
      expect(presenter).to have_received(:present_deployment_matrix).with(
        deployment_targets: deployment_targets,
        deploy_labels: deploy_labels,
        target_environments: %w[develop staging],
        pr_number: 123
      )
    end

    it 'presents the failure for an unknown environment' do
      allow(generate_matrix).to receive(:execute).and_return(Entities::Result.failure('Target environments not found in configuration: preview'))

      result = controller.resolve(pr_number: 123, environments: ['preview'])

      expect(result.error_message).to eq('Target environments not found in configuration: preview')
      expect(presenter).to have_received(:present_error).with('Target environments not found in configuration: preview')
      expect(presenter).not_to have_received(:present_deployment_matrix)
    end

    it 'presents the failure and skips the matrix when labels cannot be read' do
      allow(get_labels).to receive(:execute).and_return(Entities::Result.failure('Failed to retrieve PR labels: Not Found'))
      allow(generate_matrix).to receive(:execute)

      result = controller.resolve(pr_number: 123, environments: [])

      expect(result.error_message).to eq('Failed to retrieve PR labels: Not Found')
      expect(presenter).to have_received(:present_error).with('Failed to retrieve PR labels: Not Found')
      expect(generate_matrix).not_to have_received(:execute)
    end
  end

  describe '#targets' do
    let(:stack) { Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws' }] }]).stacks.first }
    let(:candidate) { Entities::TargetCandidate.new(stack: stack, service: 'demo', environment: nil, root: 'demo', working_directory: 'demo/aws', captures: {}) }
    let(:service_targets) { Entities::ServiceTargets.new(targets: [candidate.to_deployment_target], candidates: [candidate.to_listed_target]) }

    it 'presents the targets and candidates the use case lists' do
      allow(list_service_targets).to receive(:execute).with(service: 'demo', environments: ['develop']).and_return(Entities::Result.success(service_targets))

      result = controller.targets(service: 'demo', environments: ['develop'])

      expect(result.value).to eq(service_targets)
      expect(presenter).to have_received(:present_service_targets).with(
        service: 'demo', target_environments: ['develop'], targets: service_targets.targets, candidates: service_targets.candidates
      )
    end

    it 'presents the failure and skips the targets' do
      allow(list_service_targets).to receive(:execute).and_return(Entities::Result.failure('Target environments not found in configuration: preview'))

      result = controller.targets(service: 'demo', environments: ['preview'])

      expect(result).to be_failure
      expect(presenter).to have_received(:present_error).with('Target environments not found in configuration: preview')
      expect(presenter).not_to have_received(:present_service_targets)
    end

    it 'does not rescue presenter errors' do
      allow(list_service_targets).to receive(:execute).and_return(Entities::Result.success(service_targets))
      allow(presenter).to receive(:present_service_targets).and_raise(RuntimeError, 'GITHUB_OUTPUT is not set')

      expect { controller.targets(service: 'demo', environments: []) }.to raise_error(RuntimeError, 'GITHUB_OUTPUT is not set')
    end

    it 'does not build the label reader' do
      allow(list_service_targets).to receive(:execute).and_return(Entities::Result.success(service_targets))
      controller = described_class.new(get_labels: -> { raise 'label reader built' }, generate_matrix: generate_matrix, list_service_targets: list_service_targets, presenter: presenter)

      expect(controller.targets(service: 'demo', environments: [])).to be_success
    end
  end
end
