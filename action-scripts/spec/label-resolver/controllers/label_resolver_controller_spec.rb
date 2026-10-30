# spec/label-resolver/controllers/label_resolver_controller_spec.rb

require 'spec_helper'

RSpec.describe Interfaces::Controllers::LabelResolverController do
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
    let(:target_environments) { ['develop'] }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }
    let(:deployment_targets) { [build(:deployment_target)] }

    context 'with successful resolution flow for single environment' do
      let(:pr_result) { Entities::Result.success(deploy_labels) }
      let(:env_result) { Entities::Result.success(['develop']) }
      let(:safety_result) { Entities::Result.success('passed') }
      let(:matrix_result) { Entities::Result.success(deployment_targets) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
        allow(presenter).to receive(:present_deployment_matrix)
      end

      it 'successfully resolves deployment from labels' do
        result = controller.resolve_from_labels(pr_number: pr_number, target_environments: target_environments)

        expect(result.value).to eq(deployment_targets)

        expect(determine_target_environment_use_case).to have_received(:execute).with(target_environments: ['develop'])
        expect(validate_deployment_safety_use_case).to have_received(:execute).with(
          deploy_labels: deploy_labels,
          pr_number: pr_number
        )
        expect(generate_matrix_use_case).to have_received(:execute).with(
          deploy_labels: deploy_labels,
          target_environments: ['develop']
        )
        expect(presenter).to have_received(:present_deployment_matrix).with(
          deployment_targets: deployment_targets,
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          target_environments: ['develop'],
          safety_status: 'passed'
        )
      end
    end

    context 'with successful resolution flow for multiple environments' do
      let(:target_environments) { ['develop', 'staging'] }
      let(:pr_result) { Entities::Result.success(deploy_labels) }
      let(:env_result) { Entities::Result.success(['develop', 'staging']) }
      let(:safety_result) { Entities::Result.success('passed') }
      let(:develop_target) { build(:deployment_target, environment: 'develop') }
      let(:staging_target) { build(:deployment_target, environment: 'staging') }
      let(:matrix_result) { Entities::Result.success([develop_target, staging_target]) }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
        allow(presenter).to receive(:present_deployment_matrix)
      end

      it 'successfully resolves deployment for multiple environments' do
        controller.resolve_from_labels(pr_number: pr_number, target_environments: target_environments)

        expect(determine_target_environment_use_case).to have_received(:execute).with(target_environments: ['develop', 'staging'])
        expect(generate_matrix_use_case).to have_received(:execute).with(
          deploy_labels: deploy_labels,
          target_environments: ['develop', 'staging']
        )
        expect(presenter).to have_received(:present_deployment_matrix).with(
          deployment_targets: [develop_target, staging_target],
          deploy_labels: deploy_labels,
          pr_number: pr_number,
          target_environments: ['develop', 'staging'],
          safety_status: 'passed'
        )
      end
    end

    context 'when PR labels retrieval fails' do
      let(:pr_result) { Entities::Result.failure('PR not found') }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops execution' do
        expect(controller.resolve_from_labels(pr_number: pr_number, target_environments: ['develop'])).to be_failure

        expect(presenter).to have_received(:present_error).with('PR not found')
        expect(determine_target_environment_use_case).not_to have_received(:execute)
      end
    end

    context 'when target environment validation fails' do
      let(:pr_result) { Entities::Result.success(deploy_labels) }
      let(:env_result) { Entities::Result.failure('Invalid environment') }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops execution' do
        controller.resolve_from_labels(pr_number: pr_number, target_environments: ['develop'])

        expect(presenter).to have_received(:present_error).with('Invalid environment')
        expect(validate_deployment_safety_use_case).not_to have_received(:execute)
      end
    end

    context 'when safety validation fails' do
      let(:pr_result) { Entities::Result.success(deploy_labels) }
      let(:env_result) { Entities::Result.success(['develop']) }
      let(:safety_result) { Entities::Result.failure('Safety check failed') }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops execution' do
        controller.resolve_from_labels(pr_number: pr_number, target_environments: ['develop'])

        expect(presenter).to have_received(:present_error).with('Safety check failed')
        expect(generate_matrix_use_case).not_to have_received(:execute)
      end
    end

    context 'when matrix generation fails' do
      let(:pr_result) { Entities::Result.success(deploy_labels) }
      let(:env_result) { Entities::Result.success(['develop']) }
      let(:safety_result) { Entities::Result.success('passed') }
      let(:matrix_result) { Entities::Result.failure('Matrix generation failed') }

      before do
        allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
        allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
        allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
        allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
        allow(presenter).to receive(:present_error)
      end

      it 'presents error and stops execution' do
        controller.resolve_from_labels(pr_number: pr_number, target_environments: ['develop'])

        expect(presenter).to have_received(:present_error).with('Matrix generation failed')
        expect(presenter).not_to have_received(:present_deployment_matrix)
      end
    end
  end

  it 'passes the validated environment selection to matrix generation and presentation' do
    labels = [build(:deploy_label, :valid_service)]
    allow(get_labels_use_case).to receive(:execute).and_return(Entities::Result.success(labels))
    allow(determine_target_environment_use_case).to receive(:execute).with(target_environments: []).and_return(Entities::Result.success(%w[develop production]))
    allow(validate_deployment_safety_use_case).to receive(:execute).and_return(Entities::Result.success('passed'))
    allow(generate_matrix_use_case).to receive(:execute).and_return(Entities::Result.success([]))

    controller.resolve_from_labels(pr_number: 123, target_environments: [])

    expect(generate_matrix_use_case).to have_received(:execute).with(deploy_labels: labels, target_environments: %w[develop production])
    expect(presenter).to have_received(:present_deployment_matrix).with(deployment_targets: [], deploy_labels: labels, pr_number: 123, target_environments: %w[develop production], safety_status: 'passed')
  end

  describe '#test_deployment_workflow' do
    it 'calls resolve_from_labels with test parameters' do
      allow(controller).to receive(:resolve_from_labels)

      controller.test_deployment_workflow(pr_number: 123, target_environments: ['staging'])

      expect(controller).to have_received(:resolve_from_labels).with(pr_number: 123, target_environments: ['staging'])
    end
  end

  describe '#debug_deployment_workflow' do
    let(:pr_number) { 123 }
    let(:target_environments) { ['develop'] }
    let(:deploy_labels) { [build(:deploy_label, :valid_service)] }

    let(:pr_result) { Entities::Result.success(deploy_labels) }
    let(:env_result) { Entities::Result.success(['develop']) }
    let(:safety_result) { Entities::Result.success('passed') }
    let(:matrix_result) { Entities::Result.success([]) }

    before do
      allow(controller).to receive(:get_pr_labels_directly).and_return(pr_result)
      allow(determine_target_environment_use_case).to receive(:execute).and_return(env_result)
      allow(validate_deployment_safety_use_case).to receive(:execute).and_return(safety_result)
      allow(generate_matrix_use_case).to receive(:execute).and_return(matrix_result)
    end

    it 'executes debug workflow step by step' do
      expect { controller.debug_deployment_workflow(pr_number: pr_number, target_environments: target_environments) }.to output(/Step 1: Getting PR labels/).to_stdout

      expect(determine_target_environment_use_case).to have_received(:execute).with(target_environments: ['develop'])
      expect(validate_deployment_safety_use_case).to have_received(:execute).with(
        deploy_labels: deploy_labels,
        pr_number: pr_number
      )
      expect(generate_matrix_use_case).to have_received(:execute).with(
        deploy_labels: deploy_labels,
        target_environments: ['develop']
      )
    end
  end
end