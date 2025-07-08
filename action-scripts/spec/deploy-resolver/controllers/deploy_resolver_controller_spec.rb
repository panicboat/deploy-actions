# spec/deploy-resolver/controllers/deploy_resolver_controller_spec.rb

require 'spec_helper'

RSpec.describe Interfaces::Controllers::DeployResolverController do
  let(:determine_target_environment_use_case) { spy('DetermineTargetEnvironment') }
  let(:get_labels_use_case) { spy('GetLabels') }
  let(:validate_deployment_safety_use_case) { spy('ValidateDeploymentSafety') }
  let(:generate_matrix_use_case) { spy('GenerateMatrix') }
  let(:presenter) { spy('Presenter') }

  subject(:controller) do
    described_class.new(
      determine_target_environment_use_case: determine_target_environment_use_case,
      get_labels_use_case: get_labels_use_case,
      validate_deployment_safety_use_case: validate_deployment_safety_use_case,
      generate_matrix_use_case: generate_matrix_use_case,
      presenter: presenter
    )
  end

  describe '#resolve_from_labels' do
    let(:pr_number) { 123 }
    let(:current_branch) { 'develop' }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
    let(:target_environment) { 'develop' }
    let(:deployment_targets) { [build(:deployment_target)] }

    before do
      allow(ENV).to receive(:[]).with('GITHUB_REF_NAME').and_return(current_branch)
    end

    context 'with successful resolution flow' do
      let(:pr_result) { double('Result', success?: true, failure?: false, deploy_labels: deploy_labels) }
      let(:env_result) { double('Result', success?: true, failure?: false, target_environment: target_environment) }
      let(:safety_result) { double('Result', success?: true, failure?: false, safety_status: 'passed') }
      let(:matrix_result) { double('Result', success?: true, failure?: false, deployment_targets: deployment_targets) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
        allow(presenter).to receive(:present_deployment_matrix)
      end

      it 'successfully resolves deployment from labels' do
        controller.resolve_from_labels(pr_number: pr_number)

        expect(determine_target_environment_use_case).to have_received(:execute).with(branch_name: current_branch)
        expect(validate_deployment_safety_use_case).to have_received(:execute).with(
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          branch_name: current_branch
        )
        expect(generate_matrix_use_case).to have_received(:execute).with(
          deploy_labels: deploy_labels,
          target_environment: target_environment
        )
        expect(presenter).to have_received(:present_deployment_matrix).with(
          deployment_targets: deployment_targets,
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          branch_name: current_branch,
          target_environment: target_environment,
          safety_status: 'passed'
        )
      end
    end

    context 'when PR label retrieval fails' do
      let(:pr_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops processing' do
        controller.resolve_from_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(pr_result)
        expect(determine_target_environment_use_case).not_to have_received(:execute)
      end
    end

    context 'when environment determination fails' do
      let(:pr_result) { double('Result', success?: true, failure?: false, deploy_labels: deploy_labels) }
      let(:env_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops processing' do
        controller.resolve_from_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(env_result)
        expect(validate_deployment_safety_use_case).not_to have_received(:execute)
      end
    end

    context 'when safety validation fails' do
      let(:pr_result) { double('Result', success?: true, failure?: false, deploy_labels: deploy_labels) }
      let(:env_result) { double('Result', success?: true, failure?: false, target_environment: target_environment) }
      let(:safety_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops processing' do
        controller.resolve_from_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(safety_result)
        expect(generate_matrix_use_case).not_to have_received(:execute)
      end
    end

    context 'when matrix generation fails' do
      let(:pr_result) { double('Result', success?: true, failure?: false, deploy_labels: deploy_labels) }
      let(:env_result) { double('Result', success?: true, failure?: false, target_environment: target_environment) }
      let(:safety_result) { double('Result', success?: true, failure?: false, safety_status: 'passed') }
      let(:matrix_result) { double('Result', success?: false, failure?: true) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops processing' do
        controller.resolve_from_labels(pr_number: pr_number)

        expect(presenter).to have_received(:present_error).with(matrix_result)
      end
    end
  end

  describe '#test_deployment_workflow' do
    let(:branch_name) { 'develop' }

    before do
      allow(controller).to receive(:resolve_from_labels)
    end

    it 'tests deployment workflow with test PR number' do
      controller.test_deployment_workflow(branch_name: branch_name)

      expect(controller).to have_received(:resolve_from_labels).with(pr_number: 999)
    end

    context 'when resolve_from_labels raises error' do
      let(:error) { StandardError.new('Test error') }

      before do
        allow(controller).to receive(:resolve_from_labels).and_raise(error)
        allow(controller).to receive(:puts)
      end

      it 'catches and reports error' do
        controller.test_deployment_workflow(branch_name: branch_name)

        expect(controller).to have_received(:puts).with(/Test completed with error.*Test error/)
      end
    end
  end

  describe '#simulate_github_actions' do
    let(:branch_name) { 'develop' }
    let(:original_github_actions) { 'original_value' }
    let(:original_github_env) { '/original/path' }
    let(:original_github_ref_name) { 'original_branch' }

    before do
      allow(ENV).to receive(:[]).with('GITHUB_ACTIONS').and_return(original_github_actions)
      allow(ENV).to receive(:[]).with('GITHUB_ENV').and_return(original_github_env)
      allow(ENV).to receive(:[]).with('GITHUB_REF_NAME').and_return(original_github_ref_name)
      allow(ENV).to receive(:[]=)
      allow(File).to receive(:write)
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('TEST_VAR=test_value')
      allow(File).to receive(:delete)
      allow(controller).to receive(:resolve_from_labels)
      allow(controller).to receive(:puts)
    end

    it 'simulates GitHub Actions environment' do
      controller.simulate_github_actions(branch_name: branch_name)

      # Verify environment setup
      expect(ENV).to have_received(:[]=).with('GITHUB_ACTIONS', 'true')
      expect(ENV).to have_received(:[]=).with('GITHUB_ENV', original_github_env)
      expect(ENV).to have_received(:[]=).with('GITHUB_REF_NAME', branch_name)
      expect(File).to have_received(:write).with(original_github_env, '')

      # Verify resolve call
      expect(controller).to have_received(:resolve_from_labels).with(pr_number: 999)

      # Verify environment restoration
      expect(ENV).to have_received(:[]=).with('GITHUB_ACTIONS', original_github_actions)
      expect(ENV).to have_received(:[]=).with('GITHUB_ENV', original_github_env)
      expect(ENV).to have_received(:[]=).with('GITHUB_REF_NAME', original_github_ref_name)
    end

    it 'displays generated environment variables' do
      controller.simulate_github_actions(branch_name: branch_name)

      expect(controller).to have_received(:puts).with(/Generated Environment Variables/)
      expect(controller).to have_received(:puts).with('TEST_VAR=test_value')
    end

    context 'when environment file does not exist' do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it 'does not try to read environment file' do
        controller.simulate_github_actions(branch_name: branch_name)

        expect(File).not_to have_received(:read)
      end
    end

    it 'ensures cleanup even if error occurs' do
      allow(controller).to receive(:resolve_from_labels).and_raise(StandardError.new('Test error'))

      expect {
        controller.simulate_github_actions(branch_name: branch_name)
      }.not_to raise_error

      # Verify cleanup happened
      expect(ENV).to have_received(:[]=).with('GITHUB_ACTIONS', original_github_actions)
      expect(ENV).to have_received(:[]=).with('GITHUB_ENV', original_github_env)
      expect(ENV).to have_received(:[]=).with('GITHUB_REF_NAME', original_github_ref_name)
      expect(File).to have_received(:delete).with('/tmp/github_env')
    end
  end

  describe '#get_pr_labels_directly' do
    let(:pr_number) { 123 }

    context 'when get_labels use case is available' do
      let(:expected_result) { double('Result') }

      before do
        allow(get_labels_use_case).to receive(:execute).and_return(expected_result)
      end

      it 'executes get_labels use case' do
        result = controller.send(:get_pr_labels_directly, pr_number)

        expect(get_labels_use_case).to have_received(:execute).with(pr_number: pr_number)
        expect(result).to eq(expected_result)
      end
    end

    context 'when get_labels use case is not available' do
      let(:controller) do
        described_class.new(
          determine_target_environment_use_case: determine_target_environment_use_case,
          get_labels_use_case: nil,
          validate_deployment_safety_use_case: validate_deployment_safety_use_case,
          generate_matrix_use_case: generate_matrix_use_case,
          presenter: presenter
        )
      end

      it 'returns failure result' do
        result = controller.send(:get_pr_labels_directly, pr_number)

        expect(result).to be_failure
        expect(result.error_message).to include('GitHub client not available')
      end
    end
  end
end