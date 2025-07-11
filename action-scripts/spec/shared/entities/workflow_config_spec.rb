# spec/shared/entities/workflow_config_spec.rb

require 'spec_helper'

RSpec.describe Entities::WorkflowConfig do
  let(:config_hash) do
    {
      'environments' => [
        {
          'environment' => 'develop',
          'aws_region' => 'ap-northeast-1',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/plan-role',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/apply-role'
        },
        {
          'environment' => 'staging',
          'aws_region' => 'us-west-2',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/staging-plan',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/staging-apply'
        },
        {
          'environment' => 'production',
          'aws_region' => 'us-west-2',
          'iam_role_plan' => 'arn:aws:iam::123456789012:role/production-plan',
          'iam_role_apply' => 'arn:aws:iam::123456789012:role/production-apply'
        }
      ],
      'directory_conventions' => [
        {
          'root' => '{service}',
          'stacks' => [
            {
              'name' => 'terragrunt',
              'directory' => 'terragrunt/{environment}'
            },
            {
              'name' => 'kubernetes',
              'directory' => 'kubernetes/overlays/{environment}'
            }
          ]
        }
      ],
      'services' => [
        {
          'name' => 'test-service',
          'directory_conventions' => {
            'terragrunt' => 'services/{service}/terragrunt/envs/{environment}'
          }
        },
        {
          'name' => 'excluded-service',
          'exclude_from_automation' => true,
          'exclusion_config' => {
            'reason' => 'Manual deployment required',
            'type' => 'permanent'
          }
        }
      ],
      'branch_patterns' => {
        'develop' => 'develop',
        'staging' => 'staging',
        'production' => 'production'
      }
    }
  end

  subject(:workflow_config) { described_class.new(config_hash) }

  describe '#initialize' do
    it 'initializes with config hash' do
      expect(workflow_config.raw_config).to eq(config_hash)
    end
  end

  describe '#environments' do
    it 'returns environments hash keyed by environment name' do
      environments = workflow_config.environments
      
      expect(environments).to be_a(Hash)
      expect(environments.keys).to contain_exactly('develop', 'staging', 'production')
      expect(environments['develop']['aws_region']).to eq('ap-northeast-1')
      expect(environments['staging']['aws_region']).to eq('us-west-2')
      expect(environments['production']['aws_region']).to eq('us-west-2')
    end
  end

  describe '#services' do
    it 'returns services hash keyed by service name' do
      services = workflow_config.services
      
      expect(services).to be_a(Hash)
      expect(services.keys).to contain_exactly('test-service', 'excluded-service')
      expect(services['test-service']['name']).to eq('test-service')
      expect(services['excluded-service']['exclude_from_automation']).to be true
    end
  end

  describe '#environment_config' do
    context 'with existing environment' do
      it 'returns environment configuration' do
        config = workflow_config.environment_config('develop')
        
        expect(config['environment']).to eq('develop')
        expect(config['aws_region']).to eq('ap-northeast-1')
        expect(config['iam_role_plan']).to eq('arn:aws:iam::123456789012:role/plan-role')
      end
    end

    context 'with non-existing environment' do
      it 'returns nil' do
        config = workflow_config.environment_config('non-existing')
        expect(config).to be_nil
      end
    end
  end


  describe '#directory_conventions_for' do
    context 'with service-specific convention' do
      it 'returns service-specific convention' do
        conventions = workflow_config.directory_conventions_for('test-service', 'terragrunt')
        expect(conventions).to eq(['services/{service}/terragrunt/envs/{environment}'])
      end
    end

    context 'with default convention' do
      it 'returns default convention for service without specific configuration' do
        conventions = workflow_config.directory_conventions_for('other-service', 'terragrunt')
        expect(conventions).to eq(['{service}/terragrunt/{environment}'])
      end
    end

    context 'with non-existing stack' do
      it 'returns empty array' do
        conventions = workflow_config.directory_conventions_for('test-service', 'non-existing')
        expect(conventions).to be_empty
      end
    end
  end

  describe '#directory_convention_for' do
    context 'with service-specific convention' do
      it 'returns first service-specific convention' do
        convention = workflow_config.directory_convention_for('test-service', 'terragrunt')
        expect(convention).to eq('services/{service}/terragrunt/envs/{environment}')
      end
    end

    context 'with default convention' do
      it 'returns first default convention for service without specific configuration' do
        convention = workflow_config.directory_convention_for('other-service', 'terragrunt')
        expect(convention).to eq('{service}/terragrunt/{environment}')
      end
    end

    context 'with non-existing stack' do
      it 'returns nil' do
        convention = workflow_config.directory_convention_for('test-service', 'non-existing')
        expect(convention).to be_nil
      end
    end
  end

  describe '#directory_conventions_root' do
    it 'returns the first root pattern from directory conventions' do
      expect(workflow_config.directory_conventions_root).to eq('{service}')
    end

    it 'returns all root patterns' do
      expect(workflow_config.directory_conventions_root_patterns).to eq(['{service}'])
    end

    context 'with empty root' do
      let(:config_hash) do
        super().tap do |config|
          config['directory_conventions'][0]['root'] = ''
        end
      end

      it 'returns empty string' do
        expect(workflow_config.directory_conventions_root).to eq('')
      end
    end

    context 'with missing directory_conventions' do
      let(:config_hash) { super().except('directory_conventions') }

      it 'raises validation error' do
        expect { workflow_config }.to raise_error(/directory_conventions/)
      end
    end
  end

  describe '#branch_to_environment' do
    context 'with mapped branch' do
      it 'returns mapped environment' do
        expect(workflow_config.branch_to_environment('develop')).to eq('develop')
        expect(workflow_config.branch_to_environment('staging')).to eq('staging')
      end
    end

    context 'with unmapped branch' do
      it 'returns nil' do
        expect(workflow_config.branch_to_environment('feature/test')).to be_nil
      end
    end
  end

  describe '#safety_check_enabled?' do
    it 'always returns false (safety checks removed)' do
      expect(workflow_config.safety_check_enabled?('require_merged_pr')).to be false
      expect(workflow_config.safety_check_enabled?('any_check')).to be false
    end
  end

  describe '#excluded_services' do
    it 'returns list of excluded service names' do
      excluded = workflow_config.excluded_services
      expect(excluded).to contain_exactly('excluded-service')
    end

    context 'with no excluded services' do
      let(:config_hash) do
        super().tap do |config|
          config['services'] = [{ 'name' => 'test-service' }]
        end
      end

      it 'returns empty array' do
        excluded = workflow_config.excluded_services
        expect(excluded).to be_empty
      end
    end

    context 'with multiple root patterns' do
      let(:config_hash) do
        super().tap do |config|
          config['directory_conventions'] = [
            {
              'root' => 'apps/web/{service}',
              'stacks' => [
                {
                  'name' => 'terragrunt',
                  'directory' => 'terragrunt/{environment}'
                },
                {
                  'name' => 'kubernetes',
                  'directory' => 'kubernetes/overlays/{environment}'
                }
              ]
            },
            {
              'root' => 'services/{service}',
              'stacks' => [
                {
                  'name' => 'terragrunt',
                  'directory' => 'terragrunt/{environment}'
                },
                {
                  'name' => 'kubernetes',
                  'directory' => 'kubernetes/overlays/{environment}'
                }
              ]
            }
          ]
        end
      end

      it 'returns all possible conventions' do
        conventions = workflow_config.directory_conventions_for('other-service', 'terragrunt')
        expect(conventions).to contain_exactly(
          'apps/web/{service}/terragrunt/{environment}',
          'services/{service}/terragrunt/{environment}'
        )
      end

      it 'returns first convention for directory_convention_for' do
        convention = workflow_config.directory_convention_for('other-service', 'terragrunt')
        expect(convention).to eq('apps/web/{service}/terragrunt/{environment}')
      end

      it 'returns all root patterns' do
        roots = workflow_config.directory_conventions_root_patterns
        expect(roots).to contain_exactly('apps/web/{service}', 'services/{service}')
      end

      it 'returns first root pattern' do
        root = workflow_config.directory_conventions_root
        expect(root).to eq('apps/web/{service}')
      end

      it 'returns all directory patterns' do
        patterns = workflow_config.all_directory_patterns
        expect(patterns).to contain_exactly(
          'apps/web/{service}/terragrunt/{environment}',
          'apps/web/{service}/kubernetes/overlays/{environment}',
          'services/{service}/terragrunt/{environment}',
          'services/{service}/kubernetes/overlays/{environment}'
        )
      end
    end
  end

  describe '#validate!' do
    context 'with valid configuration' do
      it 'does not raise error' do
        expect { workflow_config.validate! }.not_to raise_error
      end
    end

    context 'with missing environments' do
      let(:config_hash) { super().except('environments') }

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/environments/)
      end
    end

    context 'with missing directory_conventions' do
      let(:config_hash) { super().except('directory_conventions') }

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/directory_conventions/)
      end
    end

    context 'with missing branch_patterns' do
      let(:config_hash) { super().except('branch_patterns') }

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/branch_patterns/)
      end
    end

    context 'with missing directory_conventions root' do
      let(:config_hash) do
        super().tap do |config|
          config['directory_conventions'] = [{ 'stacks' => [] }]
        end
      end

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/root/)
      end
    end

    context 'with missing directory_conventions stacks' do
      let(:config_hash) do
        super().tap do |config|
          config['directory_conventions'] = [{ 'root' => '{service}' }]
        end
      end

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/stacks/)
      end
    end

    context 'with non-array directory_conventions' do
      let(:config_hash) do
        super().tap do |config|
          config['directory_conventions'] = { 'root' => '{service}', 'stacks' => [] }
        end
      end

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/must be an array/)
      end
    end

    context 'with invalid environment structure' do
      let(:config_hash) do
        super().tap do |config|
          config['environments'] = [{ 'invalid' => 'structure' }]
        end
      end

      it 'raises validation error' do
        expect { workflow_config.validate! }.to raise_error(/Environment.*missing required field: environment/)
      end
    end
  end
end