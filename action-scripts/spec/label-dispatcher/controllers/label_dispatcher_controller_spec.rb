# spec/label-dispatcher/controllers/label_dispatcher_controller_spec.rb

require 'spec_helper'

RSpec.describe Interfaces::Controllers::LabelDispatcherController do
  let(:detect_services_use_case) { double('DetectChangedServices') }
  let(:manage_labels_use_case) { double('ManageLabels') }
  let(:presenter) { double('Presenter') }

  subject(:controller) do
    described_class.new(
      detect_services_use_case: detect_services_use_case,
      manage_labels_use_case: manage_labels_use_case,
      presenter: presenter
    )
  end

  describe '#dispatch_labels' do
    let(:pr_number) { 123 }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
    let(:changed_files) { ['services/test-service/main.tf'] }
    let(:excluded_services) { ['excluded-service'] }

    context 'with successful detection and no GitHub Actions' do
      let(:detection_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end

      before do
        allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return(nil)
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(presenter).to receive(:present_label_dispatch_result)
        allow(controller).to receive(:get_pr_info_from_api).and_return({})
      end

      it 'dispatches labels without GitHub integration' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(detect_services_use_case).to have_received(:execute).with(
          base_ref: nil,
          head_ref: nil
        )
        expect(presenter).to have_received(:present_label_dispatch_result).with(
          deploy_labels: deploy_labels,
          labels_added: [],
          labels_removed: [],
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end
    end

    context 'with GitHub Actions environment and PR number' do
      let(:detection_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end
      let(:manage_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          labels_added: ['deploy:test-service'],
          labels_removed: ['deploy:old-service']
        )
      end
      let(:comment_result) { double('Result', success?: true, failure?: false) }

      before do
        allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return('true')
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(manage_labels_use_case).to receive(:execute).and_return(manage_result)
        allow(manage_labels_use_case).to receive(:update_deployment_comment).and_return(comment_result)
        allow(presenter).to receive(:present_label_dispatch_result)
        allow(controller).to receive(:get_pr_info_from_api).and_return({
          base_sha: 'abc123',
          head_sha: 'def456'
        })
        allow(controller).to receive(:build_excluded_services_config).and_return({})
      end

      it 'manages GitHub labels and updates comments' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(manage_labels_use_case).to have_received(:execute).with(
          pr_number: pr_number,
          required_labels: ['deploy:test-service']
        )
        expect(manage_labels_use_case).to have_received(:update_deployment_comment).with(
          pr_number: pr_number,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: excluded_services,
          excluded_services_config: {}
        )
        expect(presenter).to have_received(:present_label_dispatch_result).with(
          deploy_labels: deploy_labels,
          labels_added: ['deploy:test-service'],
          labels_removed: ['deploy:old-service'],
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end
    end

    context 'when service detection fails' do
      let(:detection_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(presenter).to receive(:present_error)
        allow(controller).to receive(:get_pr_info_from_api).and_return({})
      end

      it 'presents error and stops processing' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(detection_result)
        expect(manage_labels_use_case).not_to have_received(:execute)
      end
    end

    context 'when label management fails' do
      let(:detection_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end
      let(:manage_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return('true')
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(manage_labels_use_case).to receive(:execute).and_return(manage_result)
        allow(presenter).to receive(:present_error)
        allow(controller).to receive(:get_pr_info_from_api).and_return({})
      end

      it 'presents error when label management fails' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(manage_result)
      end
    end

    context 'when comment update fails' do
      let(:detection_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: excluded_services
        )
      end
      let(:manage_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          labels_added: ['deploy:test-service'],
          labels_removed: []
        )
      end
      let(:comment_result) { double('Result', success?: false, failure?: true, error_message: 'Comment update failed') }

      before do
        allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return('true')
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(manage_labels_use_case).to receive(:execute).and_return(manage_result)
        allow(manage_labels_use_case).to receive(:update_deployment_comment).and_return(comment_result)
        allow(presenter).to receive(:present_label_dispatch_result)
        allow(controller).to receive(:get_pr_info_from_api).and_return({})
        allow(controller).to receive(:build_excluded_services_config).and_return({})
        allow(controller).to receive(:puts)
      end

      it 'logs warning but continues processing' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(controller).to have_received(:puts).with(/Warning.*Comment update failed/)
        expect(presenter).to have_received(:present_label_dispatch_result)
      end
    end

    context 'with API-provided refs' do
      let(:detection_result) do
        double(
          'Result',
          success?: true,
          failure?: false,
          deploy_labels: deploy_labels,
          changed_files: changed_files,
          excluded_services: []
        )
      end

      before do
        allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
        allow(presenter).to receive(:present_label_dispatch_result)
        allow(controller).to receive(:get_pr_info_from_api).and_return({
          base_sha: 'abc123def',
          head_sha: 'def456abc'
        })
        allow(controller).to receive(:puts)
      end

      it 'uses API-provided refs for detection' do
        controller.dispatch_labels(pr_number: pr_number)

        expect(detect_services_use_case).to have_received(:execute).with(
          base_ref: 'abc123def',
          head_ref: 'def456abc'
        )
        expect(controller).to have_received(:puts).with(/Using refs from API/)
      end
    end
  end

  describe '#test_detection' do
    let(:base_ref) { 'main' }
    let(:head_ref) { 'feature/test' }
    let(:detection_result) do
      double(
        'Result',
        success?: true,
        failure?: false,
        deploy_labels: [build(:deploy_label, :valid_service)],
        changed_files: ['test-file.tf'],
        excluded_services: []
      )
    end

    before do
      allow(detect_services_use_case).to receive(:execute).and_return(detection_result)
      allow(presenter).to receive(:present_label_dispatch_result)
    end

    it 'tests detection without PR interaction' do
      controller.test_detection(base_ref: base_ref, head_ref: head_ref)

      expect(detect_services_use_case).to have_received(:execute).with(
        base_ref: base_ref,
        head_ref: head_ref
      )
      expect(presenter).to have_received(:present_label_dispatch_result).with(
        deploy_labels: detection_result.deploy_labels,
        labels_added: [],
        labels_removed: [],
        changed_files: detection_result.changed_files,
        excluded_services: detection_result.excluded_services
      )
    end

    context 'when detection fails' do
      let(:detection_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(presenter).to receive(:present_error)
      end

      it 'presents error' do
        controller.test_detection(base_ref: base_ref, head_ref: head_ref)

        expect(presenter).to have_received(:present_error).with(detection_result)
      end
    end
  end

  describe '#simulate_github_actions' do
    let(:pr_number) { 123 }

    before do
      allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return('original_value')
      allow(ENV).to receive(:[]).with('GITHUB_ENV').and_return('/original/path')
      allow(ENV).to receive(:[]=)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('TEST_VAR=test_value')
      allow(File).to receive(:delete)
      allow(controller).to receive(:dispatch_labels)
      allow(controller).to receive(:puts)
    end

    it 'simulates GitHub Actions environment' do
      controller.simulate_github_actions(pr_number: pr_number)

      expect(ENV).to have_received(:[]=).with('GITHUB_ACTIONS', 'true')
      expect(ENV).to have_received(:[]=).with('GITHUB_ENV', '/tmp/github_env')
      expect(File).to have_received(:write).with('/tmp/github_env', '')
      expect(controller).to have_received(:dispatch_labels).with(pr_number: pr_number)
    end

    it 'ensures environment cleanup' do
      controller.simulate_github_actions(pr_number: pr_number)

      expect(ENV).to have_received(:[]=).with('GITHUB_ACTIONS', 'original_value')
      expect(ENV).to have_received(:[]=).with('GITHUB_ENV', '/original/path')
      expect(File).to have_received(:delete).with('/tmp/github_env')
    end
  end

  describe '#get_pr_info_from_api' do
    let(:pr_number) { 123 }
    let(:github_client) { double('GitHubClient') }
    let(:pr_info) do
      {
        title: 'Test PR',
        base_ref: 'main',
        head_ref: 'feature/test',
        base_sha: 'abc123def',
        head_sha: 'def456abc',
        labels: ['deploy:test-service']
      }
    end

    context 'when GitHub client is available' do
      before do
        allow(controller).to receive(:get_github_client).and_return(github_client)
        allow(github_client).to receive(:get_pr_info).and_return(pr_info)
        allow(controller).to receive(:puts)
      end

      it 'fetches PR information from GitHub API' do
        result = controller.send(:get_pr_info_from_api, pr_number)

        expect(github_client).to have_received(:get_pr_info).with(pr_number)
        expect(result).to include(
          base_ref: 'main',
          head_ref: 'feature/test',
          base_sha: 'abc123def',
          head_sha: 'def456abc',
          labels: ['deploy:test-service']
        )
      end
    end

    context 'when GitHub client is not available' do
      before do
        allow(controller).to receive(:get_github_client).and_return(nil)
      end

      it 'returns empty hash' do
        result = controller.send(:get_pr_info_from_api, pr_number)

        expect(result).to eq({})
      end
    end

    context 'when API call fails' do
      let(:error) { StandardError.new('API error') }

      before do
        allow(controller).to receive(:get_github_client).and_return(github_client)
        allow(github_client).to receive(:get_pr_info).and_raise(error)
        allow(controller).to receive(:puts)
      end

      it 'handles error and returns empty hash' do
        result = controller.send(:get_pr_info_from_api, pr_number)

        expect(result).to eq({})
        expect(controller).to have_received(:puts).with(/Warning.*API error/)
      end
    end
  end

  describe '#get_github_client' do
    context 'when manage_labels use case has github_client method' do
      let(:github_client) { double('GitHubClient') }

      before do
        allow(manage_labels_use_case).to receive(:respond_to?).with(:github_client).and_return(true)
        allow(manage_labels_use_case).to receive(:github_client).and_return(github_client)
      end

      it 'returns GitHub client from manage_labels' do
        client = controller.send(:get_github_client)

        expect(client).to eq(github_client)
      end
    end

    context 'when manage_labels use case has github_client instance variable' do
      let(:github_client) { double('GitHubClient') }

      before do
        allow(manage_labels_use_case).to receive(:respond_to?).with(:github_client).and_return(false)
        allow(manage_labels_use_case).to receive(:instance_variable_get).with(:@github_client).and_return(github_client)
      end

      it 'returns GitHub client from instance variable' do
        client = controller.send(:get_github_client)

        expect(client).to eq(github_client)
      end
    end

    context 'when manage_labels use case is not available' do
      let(:controller) do
        described_class.new(
          detect_services_use_case: detect_services_use_case,
          manage_labels_use_case: nil,
          presenter: presenter
        )
      end

      it 'returns nil' do
        client = controller.send(:get_github_client)

        expect(client).to be_nil
      end
    end
  end

  describe '#build_excluded_services_config' do
    let(:excluded_services) { ['service1', 'service2'] }

    before do
      # Mock Infrastructure::ConfigClient
      config_client = double('ConfigClient')
      workflow_config = double('WorkflowConfig')
      allow(Infrastructure::ConfigClient).to receive(:new).and_return(config_client)
      allow(config_client).to receive(:load_workflow_config).and_return(workflow_config)
      
      services_config = {
        'service1' => {
          'exclusion_config' => {
            'reason' => 'Custom reason 1',
            'type' => 'permanent'
          }
        },
        'service2' => {
          'exclusion_config' => {
            'reason' => 'Custom reason 2',
            'type' => 'temporary'
          }
        }
      }
      allow(workflow_config).to receive(:services).and_return(services_config)
    end

    it 'builds excluded services configuration' do
      result = controller.send(:build_excluded_services_config, excluded_services)

      expect(result).to eq({
        'service1' => {
          reason: 'Custom reason 1',
          type: 'permanent'
        },
        'service2' => {
          reason: 'Custom reason 2',
          type: 'temporary'
        }
      })
    end

    context 'with empty excluded services' do
      it 'returns empty hash' do
        result = controller.send(:build_excluded_services_config, [])

        expect(result).to eq({})
      end
    end

    context 'when config loading fails' do
      before do
        allow(Infrastructure::ConfigClient).to receive(:new).and_raise(StandardError.new('Config error'))
        allow(controller).to receive(:puts)
      end

      it 'falls back to default configuration' do
        result = controller.send(:build_excluded_services_config, excluded_services)

        expect(result).to eq({
          'service1' => {
            reason: 'Manual deployment required',
            type: 'unspecified'
          },
          'service2' => {
            reason: 'Manual deployment required',
            type: 'unspecified'
          }
        })
      end
    end
  end
end