require 'spec_helper'

RSpec.describe Interfaces::Controllers::LabelResolverController do
  let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
  let(:deployment_targets) { [build(:deployment_target)] }
  let(:get_labels) { instance_double(UseCases::LabelResolver::GetLabels) }
  let(:generate_matrix) { instance_double(UseCases::LabelResolver::GenerateMatrix) }
  let(:presenter) { instance_double(Interfaces::Presenters::ConsolePresenter, present_deployment_matrix: nil, present_error: nil) }

  subject(:controller) { described_class.new(get_labels: get_labels, generate_matrix: generate_matrix, presenter: presenter) }

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
end
