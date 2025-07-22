require 'spec_helper'

RSpec.describe Repositories::ManifestRepository do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:repository) { described_class.new(file_system_repository) }

  describe '#initialize' do
    it 'accepts a file system repository dependency' do
      expect(repository.instance_variable_get(:@file_system)).to eq(file_system_repository)
    end
  end

  describe '#find_manifests_for_environment' do
    let(:environment) { Entities::Environment.from_name('develop') }

    context 'when environment has YAML files' do
      let(:yaml_files) do
        [
          'develop/service1.yaml',
          'develop/service2.yaml',
          'develop/services/api.yaml',
          'develop/kustomization.yaml'
        ]
      end

      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('develop')
          .and_return(yaml_files)
      end

      it 'returns manifest files excluding kustomization.yaml' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(3)
        expect(result).to all(be_a(Entities::ManifestFile))
      end

      it 'filters out kustomization.yaml files' do
        allow(Entities::ManifestFile).to receive(:from_path).and_call_original

        repository.find_manifests_for_environment(environment)
        
        expect(Entities::ManifestFile).to have_received(:from_path)
          .with('develop/service1.yaml', 'develop')
        expect(Entities::ManifestFile).to have_received(:from_path)
          .with('develop/service2.yaml', 'develop')
        expect(Entities::ManifestFile).to have_received(:from_path)
          .with('develop/services/api.yaml', 'develop')
        expect(Entities::ManifestFile).not_to have_received(:from_path)
          .with('develop/kustomization.yaml', 'develop')
      end

      it 'creates ManifestFile entities for each service file' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result[0]).to be_a(Entities::ManifestFile)
        expect(result[0].path).to eq('develop/service1.yaml')
        expect(result[0].service_name).to eq('service1')
        
        expect(result[1]).to be_a(Entities::ManifestFile)
        expect(result[1].path).to eq('develop/service2.yaml')
        expect(result[1].service_name).to eq('service2')
        
        expect(result[2]).to be_a(Entities::ManifestFile)
        expect(result[2].path).to eq('develop/services/api.yaml')
        expect(result[2].service_name).to eq('api')
      end
    end

    context 'when environment has only kustomization.yaml files' do
      let(:yaml_files) do
        [
          'develop/kustomization.yaml',
          'develop/services/kustomization.yaml'
        ]
      end

      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('develop')
          .and_return(yaml_files)
      end

      it 'returns empty array when only kustomization files exist' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result).to eq([])
      end
    end

    context 'when environment has no YAML files' do
      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('develop')
          .and_return([])
      end

      it 'returns empty array when no YAML files found' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result).to eq([])
      end
    end

    context 'with different environment names' do
      let(:staging_environment) { Entities::Environment.from_name('staging') }
      let(:production_environment) { Entities::Environment.from_name('production') }

      it 'uses correct environment name for file system lookup' do
        allow(file_system_repository).to receive(:find_yaml_files).and_return([])

        repository.find_manifests_for_environment(staging_environment)
        expect(file_system_repository).to have_received(:find_yaml_files).with('staging')

        repository.find_manifests_for_environment(production_environment)
        expect(file_system_repository).to have_received(:find_yaml_files).with('production')
      end
    end

    context 'with complex directory structures' do
      let(:yaml_files) do
        [
          'develop/backend/auth/user-service.yaml',
          'develop/backend/api/core-service.yaml',
          'develop/frontend/web-app.yaml',
          'develop/database/postgres.yaml',
          'develop/backend/kustomization.yaml',
          'develop/kustomization.yaml'
        ]
      end

      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('develop')
          .and_return(yaml_files)
      end

      it 'handles nested directory structures correctly' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result.size).to eq(4)
        
        service_names = result.map(&:service_name)
        expect(service_names).to include('user-service', 'core-service', 'web-app', 'postgres')
        
        directories = result.map(&:directory)
        expect(directories).to include('backend/auth', 'backend/api', 'frontend', 'database')
      end

      it 'filters out kustomization.yaml files in nested directories' do
        allow(Entities::ManifestFile).to receive(:from_path).and_call_original

        repository.find_manifests_for_environment(environment)
        
        expect(Entities::ManifestFile).not_to have_received(:from_path)
          .with('develop/backend/kustomization.yaml', 'develop')
        expect(Entities::ManifestFile).not_to have_received(:from_path)
          .with('develop/kustomization.yaml', 'develop')
      end
    end
  end

  describe '#environment_has_manifests?' do
    let(:environment) { Entities::Environment.from_name('develop') }

    context 'when environment has manifest files' do
      before do
        allow(repository).to receive(:find_manifests_for_environment)
          .with(environment)
          .and_return([
            double('manifest1'),
            double('manifest2')
          ])
      end

      it 'returns true' do
        result = repository.environment_has_manifests?(environment)
        
        expect(result).to be true
      end
    end

    context 'when environment has no manifest files' do
      before do
        allow(repository).to receive(:find_manifests_for_environment)
          .with(environment)
          .and_return([])
      end

      it 'returns false' do
        result = repository.environment_has_manifests?(environment)
        
        expect(result).to be false
      end
    end

    context 'when environment has only kustomization files' do
      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('develop')
          .and_return(['develop/kustomization.yaml'])
      end

      it 'returns false when only kustomization files exist' do
        result = repository.environment_has_manifests?(environment)
        
        expect(result).to be false
      end
    end

    it 'uses find_manifests_for_environment to determine result' do
      allow(repository).to receive(:find_manifests_for_environment)
        .with(environment)
        .and_return([double('manifest')])

      repository.environment_has_manifests?(environment)
      
      expect(repository).to have_received(:find_manifests_for_environment).with(environment)
    end
  end

  describe 'private methods' do
    describe '#file_system' do
      it 'provides access to the file system repository' do
        # This tests the private attr_reader
        expect(repository.send(:file_system)).to eq(file_system_repository)
      end
    end
  end

  describe 'integration scenarios' do
    let(:environment) { Entities::Environment.from_name('production') }

    context 'with typical microservices structure' do
      let(:yaml_files) do
        [
          'production/services/auth/user-auth.yaml',
          'production/services/auth/token-service.yaml',
          'production/services/api/core-api.yaml',
          'production/services/api/legacy-api.yaml',
          'production/infrastructure/database.yaml',
          'production/infrastructure/redis.yaml',
          'production/frontend/web-app.yaml',
          'production/services/kustomization.yaml',
          'production/kustomization.yaml'
        ]
      end

      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('production')
          .and_return(yaml_files)
      end

      it 'correctly processes microservices structure' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result.size).to eq(7)
        expect(repository.environment_has_manifests?(environment)).to be true
        
        service_names = result.map(&:service_name)
        expect(service_names).to include(
          'user-auth', 'token-service', 'core-api', 'legacy-api',
          'database', 'redis', 'web-app'
        )
      end
    end

    context 'with empty environment' do
      before do
        allow(file_system_repository).to receive(:find_yaml_files)
          .with('production')
          .and_return([])
      end

      it 'handles empty environments correctly' do
        result = repository.find_manifests_for_environment(environment)
        
        expect(result).to be_empty
        expect(repository.environment_has_manifests?(environment)).to be false
      end
    end
  end

  describe 'error conditions' do
    let(:environment) { Entities::Environment.from_name('develop') }

    it 'propagates file system repository errors' do
      allow(file_system_repository).to receive(:find_yaml_files)
        .and_raise(StandardError, 'File system error')
      
      expect {
        repository.find_manifests_for_environment(environment)
      }.to raise_error(StandardError, 'File system error')
    end

    it 'handles ManifestFile creation errors gracefully' do
      allow(file_system_repository).to receive(:find_yaml_files)
        .and_return(['develop/invalid.yaml'])
      allow(Entities::ManifestFile).to receive(:from_path)
        .and_raise(Dry::Struct::Error, 'Invalid attributes')
      
      expect {
        repository.find_manifests_for_environment(environment)
      }.to raise_error(Dry::Struct::Error, 'Invalid attributes')
    end

    it 'handles nil environment name gracefully' do
      invalid_environment = double('environment', name: nil)
      allow(file_system_repository).to receive(:find_yaml_files)
        .with(nil)
        .and_return([])
      
      result = repository.find_manifests_for_environment(invalid_environment)
      
      expect(result).to be_empty
    end
  end
end