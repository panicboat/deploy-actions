require 'spec_helper'

RSpec.describe UseCases::GenerateAppResources do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:manifest_repository) { instance_double(Repositories::ManifestRepository) }
  let(:use_case) { described_class.new(file_system_repository, manifest_repository) }

  before do
    allow(use_case).to receive(:puts)
    allow(file_system_repository).to receive(:write_file)
  end

  describe '#initialize' do
    it 'accepts file system and manifest repository dependencies' do
      expect(use_case.instance_variable_get(:@file_system)).to eq(file_system_repository)
      expect(use_case.instance_variable_get(:@manifest_repository)).to eq(manifest_repository)
    end
  end

  describe '#call' do
    let(:environment) { Entities::Environment.from_name('develop') }

    context 'with root level manifests' do
      let(:root_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false,
          service_name: 'web-service',
          relative_path: 'web-service.yaml'
        )
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return([root_manifest])
      end

      it 'generates root resource with correct attributes' do
        use_case.call(environment, 'test-resource')

        expect(file_system_repository).to have_received(:write_file) do |path, content|
          expect(path).to eq("#{environment.apps_path}/web-service.yaml")
          expect(content).to include('name: web-service')
          expect(content).to include('namespace: flux-system')
          expect(content).to include("path: \"#{environment.path}\"")
          expect(content).to include('interval: 5m0s')
          expect(content).not_to include('targetNamespace:')
          expect(content).to include('service_name: web-service')
        end
      end
    end

    context 'with subdirectory manifests' do
      let(:nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          service_name: 'api-service',
          resource_name: 'backend-api-service',
          relative_path: 'backend/api-service.yaml',
          directory: 'backend'
        )
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return([nested_manifest])
      end

      it 'generates subdirectory resource with correct attributes' do
        use_case.call(environment, 'test-resource')

        expect(file_system_repository).to have_received(:write_file) do |path, content|
          expect(path).to eq("#{environment.apps_path}/backend/api-service.yaml")
          expect(content).to include('name: backend-api-service')
          expect(content).to include('namespace: flux-system')
          expect(content).to include("path: \"#{environment.path}/backend\"")
          expect(content).to include('interval: 5m0s')
          expect(content).not_to include('targetNamespace:')
          expect(content).to include('service_name: api-service')
        end
      end
    end

    context 'with mixed manifests' do
      let(:root_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: false,
          service_name: 'frontend',
          relative_path: 'frontend.yaml'
        )
      end

      let(:nested_manifest) do
        instance_double(Entities::ManifestFile,
          in_subdirectory?: true,
          service_name: 'database',
          resource_name: 'infrastructure-database',
          relative_path: 'infrastructure/database.yaml',
          directory: 'infrastructure'
        )
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return([root_manifest, nested_manifest])
      end

      it 'generates resources for both types' do
        use_case.call(environment, 'test-resource')

        expect(file_system_repository).to have_received(:write_file).twice
        expect(file_system_repository).to have_received(:write_file)
          .with("#{environment.apps_path}/frontend.yaml", anything)
        expect(file_system_repository).to have_received(:write_file)
          .with("#{environment.apps_path}/infrastructure/database.yaml", anything)
      end
    end

    context 'with no manifests' do
      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(environment).and_return([])
      end

      it 'does not generate any resources' do
        use_case.call(environment, 'test-resource')

        expect(file_system_repository).not_to have_received(:write_file)
      end
    end
  end

  describe 'YAML structure validation' do
    let(:environment) { Entities::Environment.from_name('production') }
    let(:manifest) do
      instance_double(Entities::ManifestFile,
        in_subdirectory?: false,
        service_name: 'test-service',
        relative_path: 'test-service.yaml'
      )
    end

    before do
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .with(environment).and_return([manifest])
    end

    it 'generates valid Kustomization YAML' do
      use_case.call(environment, 'test-resource')

      expect(file_system_repository).to have_received(:write_file) do |_, content|
        parsed_yaml = YAML.safe_load(content)
        expect(parsed_yaml['apiVersion']).to eq('kustomize.toolkit.fluxcd.io/v1')
        expect(parsed_yaml['kind']).to eq('Kustomization')
        expect(parsed_yaml['metadata']['name']).to eq('test-service')
        expect(parsed_yaml['metadata']['namespace']).to eq('flux-system')
        expect(parsed_yaml['spec']['path']).to eq('./production')
        expect(parsed_yaml['spec']['interval']).to eq('5m0s')
        expect(parsed_yaml['spec']).not_to have_key('targetNamespace')
        expect(parsed_yaml['spec']['postBuild']['substitute']['service_name']).to eq('test-service')
      end
    end
  end

  describe 'error handling' do
    let(:environment) { Entities::Environment.from_name('develop') }

    it 'propagates manifest repository errors' do
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .and_raise(StandardError, 'Repository error')

      expect {
        use_case.call(environment, 'test-resource')
      }.to raise_error(StandardError, 'Repository error')
    end

    it 'propagates file system repository errors' do
      manifest = instance_double(Entities::ManifestFile, in_subdirectory?: false, service_name: 'test')
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .and_return([manifest])
      allow(file_system_repository).to receive(:write_file)
        .and_raise(StandardError, 'File system error')

      expect {
        use_case.call(environment, 'test-resource')
      }.to raise_error(StandardError, 'File system error')
    end

    it 'propagates FluxResource creation errors' do
      manifest = instance_double(Entities::ManifestFile, in_subdirectory?: false, service_name: 'test')
      allow(manifest_repository).to receive(:find_manifests_for_environment)
        .and_return([manifest])
      allow(Entities::FluxResource).to receive(:kustomization)
        .and_raise(Dry::Struct::Error, 'Invalid attributes')

      expect {
        use_case.call(environment, 'test-resource')
      }.to raise_error(Dry::Struct::Error, 'Invalid attributes')
    end
  end

  describe 'private methods' do
    let(:environment) { Entities::Environment.from_name('develop') }

    describe '#generate_resource_for_manifest' do
      it 'calls generate_root_resource for root manifests' do
        manifest = instance_double(Entities::ManifestFile, in_subdirectory?: false)
        allow(use_case).to receive(:generate_root_resource)

        use_case.send(:generate_resource_for_manifest, environment, manifest, 'test-resource', nil)

        expect(use_case).to have_received(:generate_root_resource).with(environment, manifest, 'test-resource', nil)
      end

      it 'calls generate_subdirectory_resource for nested manifests' do
        manifest = instance_double(Entities::ManifestFile, in_subdirectory?: true)
        allow(use_case).to receive(:generate_subdirectory_resource)

        use_case.send(:generate_resource_for_manifest, environment, manifest, 'test-resource', nil)

        expect(use_case).to have_received(:generate_subdirectory_resource).with(environment, manifest, 'test-resource', nil)
      end
    end
  end

  describe 'integration scenarios' do
    let(:production_environment) { Entities::Environment.from_name('production') }

    context 'with complex microservices structure' do
      let(:manifests) do
        [
          instance_double(Entities::ManifestFile,
            in_subdirectory?: false,
            service_name: 'gateway',
            relative_path: 'gateway.yaml'
          ),
          instance_double(Entities::ManifestFile,
            in_subdirectory?: true,
            service_name: 'auth-service',
            resource_name: 'services-auth-auth-service',
            relative_path: 'services/auth/auth-service.yaml',
            directory: 'services/auth'
          ),
          instance_double(Entities::ManifestFile,
            in_subdirectory?: true,
            service_name: 'postgres',
            resource_name: 'infrastructure-database-postgres',
            relative_path: 'infrastructure/database/postgres.yaml',
            directory: 'infrastructure/database'
          )
        ]
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .with(production_environment).and_return(manifests)
      end

      it 'generates all app resources correctly' do
        use_case.call(production_environment, 'test-resource')

        expect(file_system_repository).to have_received(:write_file).exactly(3).times
        
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/apps/gateway.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/apps/services/auth/auth-service.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/apps/infrastructure/database/postgres.yaml', anything)

        expect(use_case).to have_received(:puts).exactly(3).times
      end
    end
  end
end