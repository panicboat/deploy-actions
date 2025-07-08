# spec/shared/entities/result_spec.rb

require 'spec_helper'

RSpec.describe Entities::Result do
  describe '.success' do
    context 'with data' do
      subject(:result) { described_class.success(message: 'Operation completed', count: 5) }

      it 'creates successful result with data' do
        expect(result).to be_success
        expect(result).not_to be_failure
        expect(result.message).to eq('Operation completed')
        expect(result.count).to eq(5)
      end
    end

    context 'without data' do
      subject(:result) { described_class.success }

      it 'creates successful result without data' do
        expect(result).to be_success
        expect(result).not_to be_failure
      end
    end

    context 'with complex data' do
      let(:complex_data) do
        {
          deploy_labels: [build(:deploy_label, :valid_service)],
          deployment_targets: [build(:deployment_target)],
          config: build(:workflow_config)
        }
      end
      subject(:result) { described_class.success(**complex_data) }

      it 'stores complex data structures' do
        expect(result).to be_success
        expect(result.deploy_labels).to be_an(Array)
        expect(result.deployment_targets).to be_an(Array)
        expect(result.config).to be_a(Entities::WorkflowConfig)
      end
    end
  end

  describe '.failure' do
    context 'with error message' do
      subject(:result) { described_class.failure(error_message: 'Something went wrong') }

      it 'creates failure result with error message' do
        expect(result).to be_failure
        expect(result).not_to be_success
        expect(result.error_message).to eq('Something went wrong')
      end
    end

    context 'with additional failure data' do
      subject(:result) do
        described_class.failure(
          error_message: 'Validation failed',
          validation_errors: ['Missing field: name', 'Invalid format: email'],
          error_code: 'VALIDATION_ERROR'
        )
      end

      it 'creates failure result with additional data' do
        expect(result).to be_failure
        expect(result.error_message).to eq('Validation failed')
        expect(result.validation_errors).to eq(['Missing field: name', 'Invalid format: email'])
        expect(result.error_code).to eq('VALIDATION_ERROR')
      end
    end

    context 'without error message' do
      it 'raises error when no error message provided' do
        expect {
          described_class.failure(some_data: 'value')
        }.to raise_error(ArgumentError, /error_message is required/)
      end
    end
  end

  describe 'dynamic attribute access' do
    context 'with success result' do
      subject(:result) do
        described_class.success(
          target_environment: 'develop',
          branch_name: 'feature/test',
          labels_added: ['deploy:auth'],
          has_targets: true
        )
      end

      it 'provides dynamic access to all attributes' do
        expect(result.target_environment).to eq('develop')
        expect(result.branch_name).to eq('feature/test')
        expect(result.labels_added).to eq(['deploy:auth'])
        expect(result.has_targets).to be true
      end
    end

    context 'with failure result' do
      subject(:result) do
        described_class.failure(
          error_message: 'Operation failed',
          retry_count: 3,
          last_attempt_at: Time.now
        )
      end

      it 'provides dynamic access to failure attributes' do
        expect(result.error_message).to eq('Operation failed')
        expect(result.retry_count).to eq(3)
        expect(result.last_attempt_at).to be_a(Time)
      end
    end

    context 'with non-existent attribute' do
      subject(:result) { described_class.success(existing_attr: 'value') }

      it 'returns nil for non-existent attributes' do
        expect(result.non_existent_attr).to be_nil
      end
    end
  end

  describe '#success?' do
    context 'with successful result' do
      subject(:result) { described_class.success }

      it 'returns true' do
        expect(result).to be_success
      end
    end

    context 'with failure result' do
      subject(:result) { described_class.failure(error_message: 'Error') }

      it 'returns false' do
        expect(result).not_to be_success
      end
    end
  end

  describe '#failure?' do
    context 'with failure result' do
      subject(:result) { described_class.failure(error_message: 'Error') }

      it 'returns true' do
        expect(result).to be_failure
      end
    end

    context 'with successful result' do
      subject(:result) { described_class.success }

      it 'returns false' do
        expect(result).not_to be_failure
      end
    end
  end

  describe '#respond_to?' do
    subject(:result) { described_class.success(custom_attr: 'value') }

    it 'responds to dynamic attributes' do
      expect(result).to respond_to(:custom_attr)
    end

    it 'responds to standard methods' do
      expect(result).to respond_to(:success?)
      expect(result).to respond_to(:failure?)
    end

    it 'does not respond to random methods' do
      expect(result).not_to respond_to(:random_method)
    end
  end

  describe 'immutability' do
    subject(:result) { described_class.success(data: { key: 'value' }) }

    it 'prevents modification of result state' do
      expect { result.instance_variable_set(:@success, false) }.not_to change { result.success? }
    end

    it 'data can be mutable if originally mutable' do
      result.data[:new_key] = 'new_value'
      expect(result.data[:new_key]).to eq('new_value')
    end
  end

  describe 'real-world usage patterns' do
    context 'configuration validation result' do
      subject(:result) do
        described_class.success(
          config: build(:workflow_config),
          validation_summary: 'All checks passed',
          warnings: []
        )
      end

      it 'supports configuration validation pattern' do
        expect(result).to be_success
        expect(result.config).to be_a(Entities::WorkflowConfig)
        expect(result.validation_summary).to be_present
        expect(result.warnings).to be_empty
      end
    end

    context 'deployment resolution result' do
      subject(:result) do
        described_class.success(
          deployment_targets: [build(:deployment_target)],
          target_environment: 'develop',
          safety_status: 'passed',
          pr_number: 123
        )
      end

      it 'supports deployment resolution pattern' do
        expect(result).to be_success
        expect(result.deployment_targets).to be_an(Array)
        expect(result.target_environment).to eq('develop')
        expect(result.safety_status).to eq('passed')
        expect(result.pr_number).to eq(123)
      end
    end

    context 'label management result' do
      subject(:result) do
        described_class.success(
          deploy_labels: [build(:deploy_label, :valid_service)],
          labels_added: ['deploy:auth'],
          labels_removed: ['deploy:old-service'],
          changed_files: ['services/auth/main.tf']
        )
      end

      it 'supports label management pattern' do
        expect(result).to be_success
        expect(result.deploy_labels).to be_an(Array)
        expect(result.labels_added).to include('deploy:auth')
        expect(result.labels_removed).to include('deploy:old-service')
        expect(result.changed_files).to be_an(Array)
      end
    end

    context 'API failure result' do
      subject(:result) do
        described_class.failure(
          error_message: 'GitHub API rate limit exceeded',
          status_code: 403,
          retry_after: 3600,
          request_id: 'abc123'
        )
      end

      it 'supports API failure pattern' do
        expect(result).to be_failure
        expect(result.error_message).to include('rate limit')
        expect(result.status_code).to eq(403)
        expect(result.retry_after).to eq(3600)
        expect(result.request_id).to eq('abc123')
      end
    end
  end

  describe 'error handling edge cases' do
    context 'when creating failure with nil error message' do
      it 'raises argument error' do
        expect {
          described_class.failure(error_message: nil)
        }.to raise_error(ArgumentError, /error_message is required/)
      end
    end

    context 'when creating failure with empty error message' do
      it 'raises argument error' do
        expect {
          described_class.failure(error_message: '')
        }.to raise_error(ArgumentError, /error_message is required/)
      end
    end

    context 'when creating success with conflicting data' do
      subject(:result) do
        described_class.success(
          success: false,  # This would be confusing but should be allowed
          error_message: 'This should not affect success status'
        )
      end

      it 'maintains success status regardless of data content' do
        expect(result).to be_success
        expect(result.success).to be false  # The data attribute
        expect(result.error_message).to eq('This should not affect success status')
      end
    end
  end
end