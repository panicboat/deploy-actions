require 'spec_helper'

RSpec.describe Interfaces::Controllers::LabelDispatcherController do
  let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
  let(:changed_files) { ['services/test-service/main.tf'] }
  let(:detection) { UseCases::LabelManagement::Detection.new(deploy_labels: deploy_labels, changed_files: changed_files) }
  let(:dispatch_labels) { instance_double(UseCases::LabelManagement::DispatchLabels) }
  let(:detect_changed_services) { instance_double(UseCases::LabelManagement::DetectChangedServices) }
  let(:presenter) { instance_double(Interfaces::Presenters::ConsolePresenter, present_label_dispatch_result: nil, present_error: nil) }

  subject(:controller) do
    described_class.new(dispatch_labels: -> { dispatch_labels }, detect_changed_services: detect_changed_services, presenter: presenter)
  end

  describe '#dispatch' do
    it 'presents the detected and synced labels' do
      dispatch = UseCases::LabelManagement::Dispatch.new(detection: detection, labels_added: ['deploy:test-service'], labels_removed: ['deploy:old-service'])
      allow(dispatch_labels).to receive(:execute).with(pr_number: 123).and_return(Entities::Result.success(dispatch))

      expect(controller.dispatch(pr_number: 123)).to be_success
      expect(presenter).to have_received(:present_label_dispatch_result).with(
        deploy_labels: deploy_labels,
        labels_added: ['deploy:test-service'],
        labels_removed: ['deploy:old-service'],
        changed_files: changed_files
      )
    end

    it 'presents the error and returns the failure' do
      allow(dispatch_labels).to receive(:execute).and_return(Entities::Result.failure('Failed to get PR info: not found'))

      expect(controller.dispatch(pr_number: 123).error_message).to eq('Failed to get PR info: not found')
      expect(presenter).to have_received(:present_error).with('Failed to get PR info: not found')
      expect(presenter).not_to have_received(:present_label_dispatch_result)
    end
  end

  describe '#test' do
    it 'presents detection without label changes' do
      allow(detect_changed_services).to receive(:execute).with(base_ref: 'main', head_ref: 'feature/test').and_return(Entities::Result.success(detection))

      expect(controller.test(base_ref: 'main', head_ref: 'feature/test')).to be_success
      expect(presenter).to have_received(:present_label_dispatch_result).with(
        deploy_labels: deploy_labels,
        labels_added: [],
        labels_removed: [],
        changed_files: changed_files
      )
    end

    it 'does not build the dispatch use case' do
      allow(detect_changed_services).to receive(:execute).and_return(Entities::Result.success(detection))
      controller = described_class.new(dispatch_labels: -> { raise 'GITHUB_TOKEN and GITHUB_REPOSITORY are required' }, detect_changed_services: detect_changed_services, presenter: presenter)

      expect(controller.test(base_ref: nil, head_ref: nil)).to be_success
    end

    it 'presents the error and returns the failure' do
      allow(detect_changed_services).to receive(:execute).and_return(Entities::Result.failure('detection failed'))

      expect(controller.test(base_ref: 'main', head_ref: 'feature/test')).to be_failure
      expect(presenter).to have_received(:present_error).with('detection failed')
    end
  end
end
