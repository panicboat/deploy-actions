# spec/label-dispatcher/use_cases/detect_changed_services_spec.rb

require 'spec_helper'

RSpec.describe UseCases::LabelManagement::DetectChangedServices do
  let(:file_client) { double('FileSystemClient') }
  let(:config_client) { double('ConfigClient') }
  let(:config) { build(:workflow_config) }
  
  subject(:use_case) do
    described_class.new(
      file_client: file_client,
      config_client: config_client
    )
  end

  before do
    allow(config_client).to receive(:load_workflow_config).and_return(config)
  end

  describe '#execute' do
    let(:base_ref) { 'main' }
    let(:head_ref) { 'feature/test' }
    let(:changed_files) { ['services/auth/terragrunt/main.tf', 'services/payment/kubernetes/deployment.yaml'] }

    context 'with valid changed files' do
      before do
        allow(file_client).to receive(:get_changed_files).with(base_ref: base_ref, head_ref: head_ref).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('auth', 'terragrunt').and_return('services/auth/terragrunt')
        allow(config).to receive(:directory_convention_for).with('payment', 'kubernetes').and_return('services/payment/kubernetes')
        allow(config).to receive(:services).and_return({
          'auth' => { 'name' => 'auth' },
          'payment' => { 'name' => 'payment' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/{environment}' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => 'services/{service}',
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
            { 'name' => 'kubernetes', 'directory' => 'kubernetes/{environment}' }
          ]
        })
        allow(config).to receive(:directory_conventions_config).and_return([
          {
            'root' => 'services/{service}',
            'stacks' => [
              { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
              { 'name' => 'kubernetes', 'directory' => 'kubernetes/{environment}' }
            ]
          }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'detects changed services from file paths' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to contain_exactly('deploy:auth', 'deploy:payment')
        expect(result.changed_files).to eq(changed_files)
        expect(result.excluded_services).to be_empty
      end
    end

    context 'with excluded services' do
      let(:changed_files) { ['services/auth/terragrunt/main.tf', 'services/excluded-service/terragrunt/main.tf'] }

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('auth', 'terragrunt').and_return('services/auth/terragrunt')
        allow(config).to receive(:directory_convention_for).with('excluded-service', 'terragrunt').and_return('services/excluded-service/terragrunt')
        allow(config).to receive(:services).and_return({
          'auth' => { 'name' => 'auth' },
          'excluded-service' => { 'name' => 'excluded-service' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => 'services/{service}',
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
          ]
        })
        allow(config).to receive(:excluded_services).and_return(['excluded-service'])
      end

      it 'excludes services from automation but includes in results' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to contain_exactly('deploy:auth')
        expect(result.excluded_services).to contain_exactly('excluded-service')
      end
    end

    context 'with no matching files' do
      let(:changed_files) { ['README.md', 'docs/guide.md'] }

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
      end

      it 'returns empty deploy labels' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels).to be_empty
        expect(result.changed_files).to eq(changed_files)
        expect(result.excluded_services).to be_empty
      end
    end

    context 'with complex directory patterns' do
      let(:changed_files) do
        [
          'infrastructures/auth/terragrunt/envs/develop/main.tf',
          'apps/frontend/kubernetes/overlays/develop/deployment.yaml',
          'services/legacy/old-structure/main.tf'
        ]
      end

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        
        # Mock custom directory conventions
        allow(config).to receive(:directory_convention_for).with('auth', 'terragrunt').and_return('infrastructures/auth/terragrunt')
        allow(config).to receive(:directory_convention_for).with('frontend', 'kubernetes').and_return('apps/frontend/kubernetes')
        allow(config).to receive(:directory_convention_for).with('legacy', anything).and_return(nil)
        
        allow(config).to receive(:services).and_return({
          'auth' => { 'name' => 'auth' },
          'frontend' => { 'name' => 'frontend' },
          'legacy' => { 'name' => 'legacy' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'infrastructures/{service}/terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'apps/{service}/kubernetes/overlays/{environment}' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => '',  # Empty root for custom patterns
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'infrastructures/{service}/terragrunt/{environment}' },
            { 'name' => 'kubernetes', 'directory' => 'apps/{service}/kubernetes/overlays/{environment}' }
          ]
        })
        allow(config).to receive(:directory_conventions_config).and_return([
          {
            'root' => '',
            'stacks' => [
              { 'name' => 'terragrunt', 'directory' => 'infrastructures/{service}/terragrunt/{environment}' },
              { 'name' => 'kubernetes', 'directory' => 'apps/{service}/kubernetes/overlays/{environment}' }
            ]
          }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'matches services with custom directory patterns' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to contain_exactly('deploy:auth', 'deploy:frontend')
      end
    end

    context 'when file client fails' do
      let(:error) { StandardError.new('Git command failed') }

      before do
        allow(file_client).to receive(:get_changed_files).and_raise(error)
      end

      it 'returns failure result' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_failure
        expect(result.error_message).to include('Git command failed')
      end
    end

    context 'when config loading fails' do
      let(:error) { StandardError.new('Config file not found') }

      before do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
      end

      it 'returns failure result' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_failure
        expect(result.error_message).to include('Config file not found')
      end
    end

    context 'with nil refs (working directory comparison)' do
      before do
        allow(file_client).to receive(:get_changed_files).with(base_ref: nil, head_ref: nil).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).and_return('services/auth/terragrunt')
        allow(config).to receive(:services).and_return({'auth' => { 'name' => 'auth' }})
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'handles nil refs for working directory comparison' do
        result = use_case.execute(base_ref: nil, head_ref: nil)

        expect(result).to be_success
        expect(file_client).to have_received(:get_changed_files).with(base_ref: nil, head_ref: nil)
      end
    end

    context 'with service name extraction edge cases' do
      let(:changed_files) do
        [
          'services/my-service-name/main.tf',
          'services/service_with_underscores/main.tf',
          'services/123-numeric-service/main.tf',
          'not-a-service-path/main.tf'
        ]
      end

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('my-service-name', 'terragrunt').and_return('services/{service}')
        allow(config).to receive(:directory_convention_for).with('service_with_underscores', 'terragrunt').and_return('services/{service}')
        allow(config).to receive(:directory_convention_for).with('123-numeric-service', 'terragrunt').and_return('services/{service}')
        allow(config).to receive(:services).and_return({
          'my-service-name' => { 'name' => 'my-service-name' },
          'service_with_underscores' => { 'name' => 'service_with_underscores' },
          '123-numeric-service' => { 'name' => '123-numeric-service' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => '' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => 'services/{service}',
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => '' }
          ]
        })
        allow(config).to receive(:directory_conventions_config).and_return([
          {
            'root' => 'services/{service}',
            'stacks' => [
              { 'name' => 'terragrunt', 'directory' => '' }
            ]
          }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'handles various service naming patterns' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        service_names = result.deploy_labels.map { |label| label.to_s.sub('deploy:', '') }
        expect(service_names).to include('my-service-name', 'service_with_underscores', '123-numeric-service')
      end
    end

    context 'with multiple stacks for same service' do
      let(:changed_files) do
        [
          'services/auth/terragrunt/main.tf',
          'services/auth/kubernetes/overlays/develop/deployment.yaml'
        ]
      end

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('auth', 'terragrunt').and_return('services/{service}/terragrunt')
        allow(config).to receive(:directory_convention_for).with('auth', 'kubernetes').and_return('services/{service}/kubernetes')
        allow(config).to receive(:services).and_return({
          'auth' => { 'name' => 'auth' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
          { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => 'services/{service}',
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
            { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
          ]
        })
        allow(config).to receive(:directory_conventions_config).and_return([
          {
            'root' => 'services/{service}',
            'stacks' => [
              { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' },
              { 'name' => 'kubernetes', 'directory' => 'kubernetes/overlays/{environment}' }
            ]
          }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'creates single deploy label for service with multiple stack changes' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to eq(['deploy:auth'])
      end
    end

    context 'with non-existent service in configuration' do
      let(:changed_files) { ['services/unknown-service/main.tf'] }

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('unknown-service', anything).and_return('services/{service}')
        allow(config).to receive(:services).and_return({})
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
        ])
        allow(config).to receive(:excluded_services).and_return([])
      end

      it 'skips services not in configuration' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels).to be_empty
      end
    end
  end

  describe 'service detection logic' do
    let(:base_ref) { 'main' }
    let(:head_ref) { 'feature/test' }

    before do
      allow(config_client).to receive(:load_workflow_config).and_return(config)
      allow(config).to receive(:excluded_services).and_return([])
    end

    context 'with default directory conventions' do
      let(:changed_files) { ['auth/terragrunt/envs/develop/main.tf'] }

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('auth', 'terragrunt').and_return('{service}/terragrunt/envs/{environment}')
        allow(config).to receive(:services).and_return({
          'auth' => { 'name' => 'auth' }
        })
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terragrunt/{environment}' }
        ])
      end

      it 'detects service using default pattern' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to include('deploy:auth')
      end
    end

    context 'with service-specific directory conventions' do
      let(:changed_files) { ['infrastructures/special-service/terraform/main.tf'] }

      before do
        allow(file_client).to receive(:get_changed_files).and_return(changed_files)
        allow(config).to receive(:directory_convention_for).with('special-service', 'terragrunt').and_return('infrastructures/{service}/terraform')
        allow(config).to receive(:services).and_return({
          'special-service' => {
            'name' => 'special-service',
            'directory_conventions' => {
              'terragrunt' => 'infrastructures/{service}/terraform'
            }
          }
        })
        allow(config).to receive(:excluded_services).and_return([])
        allow(config).to receive(:send).with(:directory_stacks).and_return([
          { 'name' => 'terragrunt', 'directory' => 'terraform' }
        ])
        allow(config).to receive(:directory_conventions).and_return({
          'root' => 'infrastructures/{service}',
          'stacks' => [
            { 'name' => 'terragrunt', 'directory' => 'terraform' }
          ]
        })
        allow(config).to receive(:directory_conventions_config).and_return([
          {
            'root' => 'infrastructures/{service}',
            'stacks' => [
              { 'name' => 'terragrunt', 'directory' => 'terraform' }
            ]
          }
        ])
      end

      it 'detects service using custom pattern' do
        result = use_case.execute(base_ref: base_ref, head_ref: head_ref)

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to include('deploy:special-service')
      end
    end
  end

  describe 'integration with real components' do
    let(:real_file_client) { Infrastructure::FileSystemClient.new }
    let(:real_config_client) { Infrastructure::ConfigClient.new }
    let(:use_case) do
      described_class.new(
        file_client: real_file_client,
        config_client: real_config_client
      )
    end
    let(:temp_config) { create_test_config(default_test_config) }

    after { temp_config.unlink }

    context 'with mocked git operations' do
      before do
        allow(real_file_client).to receive(:get_changed_files).and_return(['test-service/terragrunt/develop/main.tf'])
      end

      it 'works with real configuration and mocked file operations' do
        result = use_case.execute(base_ref: 'main', head_ref: 'feature/test')

        expect(result).to be_success
        expect(result.deploy_labels.map(&:to_s)).to include('deploy:test-service')
      end
    end
  end
end