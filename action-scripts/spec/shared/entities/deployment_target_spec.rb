# spec/shared/entities/deployment_target_spec.rb

require 'spec_helper'

RSpec.describe Entities::DeploymentTarget do
  describe '#initialize' do
    context 'with all required core fields' do
      it 'creates a target' do
        target = described_class.new(
          service: 'foo',
          stack: 'terragrunt',
          working_directory: 'foo/terragrunt/develop',
          environment: 'develop',
          stack_convention_root: 'foo',
          attributes: { 'aws_region' => 'ap-northeast-1' }
        )
        expect(target.service).to eq('foo')
        expect(target.stack).to eq('terragrunt')
        expect(target.working_directory).to eq('foo/terragrunt/develop')
        expect(target.environment).to eq('develop')
        expect(target.stack_convention_root).to eq('foo')
        expect(target.attributes).to eq('aws_region' => 'ap-northeast-1')
      end
    end

    context 'with environment-agnostic stack' do
      it 'allows nil environment' do
        target = described_class.new(
          service: 'foo',
          stack: 'docker',
          working_directory: 'foo/workspace',
          attributes: {}
        )
        expect(target.environment).to be_nil
        expect(target.attributes).to eq({})
      end
    end

    context 'with empty attributes' do
      it 'defaults attributes to empty hash' do
        target = described_class.new(
          service: 'foo',
          stack: 'kubernetes',
          working_directory: 'foo/kubernetes/overlays/develop',
          environment: 'develop'
        )
        expect(target.attributes).to eq({})
      end
    end

    context 'when service is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: nil, stack: 'terragrunt', working_directory: 'foo')
        }.to raise_error(ArgumentError, /service/)
      end
    end

    context 'when stack is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: 'foo', stack: nil, working_directory: 'foo/dir')
        }.to raise_error(ArgumentError, /stack/)
      end
    end

    context 'when working_directory is missing' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: 'foo', stack: 'terragrunt', working_directory: nil)
        }.to raise_error(ArgumentError, /working_directory/)
      end
    end

    context 'when service is empty string' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(service: '', stack: 'terragrunt', working_directory: 'foo/dir')
        }.to raise_error(ArgumentError, /service/)
      end
    end
  end

  describe '#to_matrix_item' do
    it 'returns flat hash merging core attrs and attributes with symbol keys' do
      target = described_class.new(
        service: 'foo',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        environment: 'develop',
        stack_convention_root: 'foo',
        attributes: {
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123:role/plan',
          'iam_role_apply' => 'arn:aws:iam::123:role/apply'
        }
      )

      expect(target.to_matrix_item).to eq(
        service: 'foo',
        environment: 'develop',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        stack_convention_root: 'foo',
        aws_region: 'ap-northeast-1',
        iam_role_plan: 'arn:aws:iam::123:role/plan',
        iam_role_apply: 'arn:aws:iam::123:role/apply'
      )
    end

    it 'omits attribute keys when attributes is empty' do
      target = described_class.new(
        service: 'foo',
        stack: 'kubernetes',
        working_directory: 'foo/kubernetes/overlays/develop',
        environment: 'develop',
        stack_convention_root: 'foo'
      )

      expect(target.to_matrix_item).to eq(
        service: 'foo',
        environment: 'develop',
        stack: 'kubernetes',
        working_directory: 'foo/kubernetes/overlays/develop',
        stack_convention_root: 'foo'
      )
    end
  end

  describe '#==' do
    let(:base_args) do
      {
        service: 'foo',
        stack: 'terragrunt',
        working_directory: 'foo/terragrunt/develop',
        environment: 'develop'
      }
    end

    it 'is equal when service / environment / stack / working_directory match' do
      a = described_class.new(**base_args, attributes: { 'k' => 'v1' })
      b = described_class.new(**base_args, attributes: { 'k' => 'v2' })
      expect(a).to eq(b)
      expect(a.hash).to eq(b.hash)
    end

    it 'is not equal when working_directory differs' do
      a = described_class.new(**base_args)
      b = described_class.new(**base_args.merge(working_directory: 'foo/other'))
      expect(a).not_to eq(b)
    end
  end
end
