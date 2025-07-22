require 'spec_helper'

RSpec.describe UseCases::GenerateAppsKustomization do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:manifest_repository) { instance_double(Repositories::ManifestRepository) }
  let(:use_case) { described_class.new(file_system_repository, manifest_repository) }

  before do
    allow(use_case).to receive(:puts)
  end

  describe '#initialize' do
    it 'accepts file system and manifest repository dependencies' do
      expect(use_case.instance_variable_get(:@file_system)).to eq(file_system_repository)
      expect(use_case.instance_variable_get(:@manifest_repository)).to eq(manifest_repository)
    end
  end

  describe '#call' do
    let(:environment) { Entities::Environment.from_name('develop') }

    before do
      allow(file_system_repository).to receive(:write_file)
      allow(file_system_repository).to receive(:ensure_directory)
    end

    context 'when manifests exist' do
      let(:manifest1) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false,
          service_name: 'web-service',
          relative_path: 'web-service.yaml',
          directory: '.'
        )
      end

      let(:manifest2) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          service_name: 'api-service',
          relative_path: 'backend/api-service.yaml',
          directory: 'backend'
        )
      end

      let(:manifests) { [manifest1, manifest2] }

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return(manifests)
      end

      it 'builds correct resources list' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          expect(content).to include('- web-service.yaml')
          expect(content).to include('- backend/api-service.yaml')
        end
      end

      it 'ensures subdirectories for nested manifests' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:ensure_directory)
          .with("#{environment.apps_path}/backend")
      end

      it 'writes kustomization to correct path' do
        expected_path = "#{environment.apps_path}/kustomization.yaml"
        
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file)
          .with(expected_path, anything)
      end

      it 'outputs success message' do
        use_case.call(environment)

        expect(use_case).to have_received(:puts)
          .with("📝 Generated apps kustomization for #{environment.name}")
      end
    end

    context 'when no manifests exist' do
      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return([])
      end

      it 'creates empty resources kustomization' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          expect(content).to include('resources: []')
        end
      end

      it 'shows warning message' do
        use_case.call(environment)

        expect(use_case).to have_received(:puts)
          .with("⚠️  No YAML files found in #{environment.name} directory")
      end

      it 'does not ensure any subdirectories' do
        use_case.call(environment)

        expect(file_system_repository).not_to have_received(:ensure_directory)
      end
    end

    context 'with mixed root and nested manifests' do
      let(:root_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false,
          service_name: 'frontend',
          relative_path: 'frontend.yaml',
          directory: '.'
        )
      end

      let(:nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          service_name: 'database',
          relative_path: 'infrastructure/database.yaml',
          directory: 'infrastructure'
        )
      end

      let(:deeply_nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          service_name: 'auth-service',
          relative_path: 'services/auth/auth-service.yaml',
          directory: 'services/auth'
        )
      end

      let(:manifests) { [root_manifest, nested_manifest, deeply_nested_manifest] }

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return(manifests)
      end

      it 'handles mixed manifest types correctly' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          expect(content).to include('- frontend.yaml')
          expect(content).to include('- infrastructure/database.yaml')
          expect(content).to include('- services/auth/auth-service.yaml')
        end
      end

      it 'ensures all required subdirectories' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:ensure_directory)
          .with("#{environment.apps_path}/infrastructure")
        expect(file_system_repository).to have_received(:ensure_directory)
          .with("#{environment.apps_path}/services/auth")
        expect(file_system_repository).to have_received(:ensure_directory).twice
      end
    end
  end

  describe 'YAML structure validation' do
    let(:environment) { Entities::Environment.from_name('develop') }
    let(:manifest) do
      instance_double(Entities::ManifestFile,
        in_subdirectory?: false,
        service_name: 'test-service',
        relative_path: 'test-service.yaml',
        directory: '.'
      )
    end

    before do
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .with(environment).and_return([manifest])
      allow(file_system_repository).to receive(:write_file)
      allow(file_system_repository).to receive(:ensure_directory)
    end

    it 'generates valid YAML structure' do
      use_case.call(environment)

      expect(file_system_repository).to have_received(:write_file) do |_, content|
        parsed_yaml = YAML.safe_load(content)
        expect(parsed_yaml['apiVersion']).to eq('kustomize.config.k8s.io/v1beta1')
        expect(parsed_yaml['kind']).to eq('Kustomization')
        expect(parsed_yaml['resources']).to eq(['test-service.yaml'])
        expect(parsed_yaml).not_to have_key('metadata')
      end
    end

    it 'removes empty metadata from YAML content' do
      use_case.call(environment)

      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).not_to include('metadata: {}')
        expect(content).not_to include('metadata:')
      end
    end
  end

  describe 'error handling' do
    let(:environment) { Entities::Environment.from_name('develop') }

    before do
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .with(environment).and_return([])
    end

    it 'propagates manifest repository errors' do
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .and_raise(StandardError, 'Repository error')

      expect {
        use_case.call(environment)
      }.to raise_error(StandardError, 'Repository error')
    end

    it 'propagates file system repository errors' do
      allow(file_system_repository).to receive(:write_file)
        .and_raise(StandardError, 'File system error')

      expect {
        use_case.call(environment)
      }.to raise_error(StandardError, 'File system error')
    end

    it 'propagates FluxResource creation errors' do
      allow(Entities::FluxResource).to receive(:kustomize_config)
        .and_raise(Dry::Struct::Error, 'Invalid attributes')

      expect {
        use_case.call(environment)
      }.to raise_error(Dry::Struct::Error, 'Invalid attributes')
    end
  end

  describe 'private methods' do
    describe '#build_resources_list' do
      let(:environment) { Entities::Environment.from_name('develop') }
      
      let(:root_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false,
          service_name: 'root-service'
        )
      end

      let(:nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          relative_path: 'nested/service.yaml'
        )
      end

      it 'builds correct resource paths' do
        manifests = [root_manifest, nested_manifest]
        
        result = use_case.send(:build_resources_list, environment, manifests)
        
        expect(result).to eq(['root-service.yaml', 'nested/service.yaml'])
      end
    end

    describe '#ensure_subdirectories' do
      let(:environment) { Entities::Environment.from_name('develop') }
      
      let(:nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          directory: 'services/backend'
        )
      end

      let(:root_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false
        )
      end

      before do
        allow(file_system_repository).to receive(:ensure_directory)
      end

      it 'ensures directories only for nested manifests' do
        manifests = [root_manifest, nested_manifest]
        
        use_case.send(:ensure_subdirectories, environment, manifests)
        
        expect(file_system_repository).to have_received(:ensure_directory)
          .with("#{environment.apps_path}/services/backend")
        expect(file_system_repository).to have_received(:ensure_directory).once
      end
    end
  end

  describe 'integration scenarios' do
    let(:production_environment) { Entities::Environment.from_name('production') }

    before do
      allow(file_system_repository).to receive(:write_file)
      allow(file_system_repository).to receive(:ensure_directory)
    end

    context 'with complex microservices structure' do
      let(:manifests) do
        [
          instance_double(Entities::ManifestFile,
            in_subdirectory?: false,
            service_name: 'gateway',
            relative_path: 'gateway.yaml',
            directory: '.'
          ),
          instance_double(Entities::ManifestFile,
            in_subdirectory?: true,
            service_name: 'auth-service',
            relative_path: 'services/auth/auth-service.yaml',
            directory: 'services/auth'
          ),
          instance_double(Entities::ManifestFile,
            in_subdirectory?: true,
            service_name: 'user-service',
            relative_path: 'services/user/user-service.yaml',
            directory: 'services/user'
          ),
          instance_double(Entities::ManifestFile,
            in_subdirectory?: true,
            service_name: 'postgres',
            relative_path: 'infrastructure/database/postgres.yaml',
            directory: 'infrastructure/database'
          )
        ]
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(production_environment).and_return(manifests)
      end

      it 'handles complex structure correctly' do
        use_case.call(production_environment)

        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/apps/kustomization.yaml', anything)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          expect(content).to include('- gateway.yaml')
          expect(content).to include('- services/auth/auth-service.yaml')
          expect(content).to include('- services/user/user-service.yaml')
          expect(content).to include('- infrastructure/database/postgres.yaml')
        end

        expect(file_system_repository).to have_received(:ensure_directory)
          .with('./clusters/production/apps/services/auth')
        expect(file_system_repository).to have_received(:ensure_directory)
          .with('./clusters/production/apps/services/user')
        expect(file_system_repository).to have_received(:ensure_directory)
          .with('./clusters/production/apps/infrastructure/database')
      end
    end
  end
end