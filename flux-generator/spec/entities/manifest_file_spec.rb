require 'spec_helper'

RSpec.describe Entities::ManifestFile do
  describe '.from_path' do
    context 'with root level file' do
      let(:manifest_file) do
        described_class.from_path('develop/service.yaml', 'develop')
      end

      it 'creates manifest file with correct attributes' do
        expect(manifest_file.path).to eq('develop/service.yaml')
        expect(manifest_file.relative_path).to eq('service.yaml') 
        expect(manifest_file.service_name).to eq('service')
        expect(manifest_file.directory).to eq('.')
      end
    end

    context 'with nested file' do
      let(:manifest_file) do
        described_class.from_path('develop/microservices/api-service.yaml', 'develop')
      end

      it 'creates manifest file with correct nested attributes' do
        expect(manifest_file.path).to eq('develop/microservices/api-service.yaml')
        expect(manifest_file.relative_path).to eq('microservices/api-service.yaml')
        expect(manifest_file.service_name).to eq('api-service')
        expect(manifest_file.directory).to eq('microservices')
      end
    end

    context 'with deeply nested file' do
      let(:manifest_file) do
        described_class.from_path('/path/to/develop/services/backend/database.yaml', '/path/to/develop')
      end

      it 'creates manifest file with deeply nested attributes' do
        expect(manifest_file.path).to eq('/path/to/develop/services/backend/database.yaml')
        expect(manifest_file.relative_path).to eq('services/backend/database.yaml')
        expect(manifest_file.service_name).to eq('database')
        expect(manifest_file.directory).to eq('services/backend')
      end
    end

    context 'with environment path containing special characters' do
      let(:manifest_file) do
        described_class.from_path('/path/to/my-env/services/web-app.yaml', '/path/to/my-env')
      end

      it 'handles special characters in environment path' do
        expect(manifest_file.relative_path).to eq('services/web-app.yaml')
        expect(manifest_file.service_name).to eq('web-app')
        expect(manifest_file.directory).to eq('services')
      end
    end

    context 'with absolute environment path in full path' do
      let(:manifest_file) do
        described_class.from_path('/absolute/path/staging/app/service.yaml', '/absolute/path/staging')
      end

      it 'correctly removes absolute environment path' do
        expect(manifest_file.relative_path).to eq('app/service.yaml')
        expect(manifest_file.service_name).to eq('service')
        expect(manifest_file.directory).to eq('app')
      end
    end
  end

  describe '#in_subdirectory?' do
    context 'when file is in root directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/service.yaml',
          relative_path: 'service.yaml',
          service_name: 'service',
          directory: '.'
        )
      end

      it 'returns false' do
        expect(manifest_file.in_subdirectory?).to be false
      end
    end

    context 'when file is in subdirectory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/services/api.yaml',
          relative_path: 'services/api.yaml',
          service_name: 'api',
          directory: 'services'
        )
      end

      it 'returns true' do
        expect(manifest_file.in_subdirectory?).to be true
      end
    end

    context 'when file is in deeply nested directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/apps/backend/database.yaml',
          relative_path: 'apps/backend/database.yaml',
          service_name: 'database',
          directory: 'apps/backend'
        )
      end

      it 'returns true' do
        expect(manifest_file.in_subdirectory?).to be true
      end
    end
  end

  describe '#resource_name' do
    context 'when file is in root directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/service.yaml',
          relative_path: 'service.yaml',
          service_name: 'service',
          directory: '.'
        )
      end

      it 'returns the service name' do
        expect(manifest_file.resource_name).to eq('service')
      end
    end

    context 'when file is in subdirectory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/services/api-service.yaml',
          relative_path: 'services/api-service.yaml',
          service_name: 'api-service',
          directory: 'services'
        )
      end

      it 'returns flattened path with dashes' do
        expect(manifest_file.resource_name).to eq('services-api-service')
      end
    end

    context 'when file is in deeply nested directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/apps/backend/database.yaml',
          relative_path: 'apps/backend/database.yaml',
          service_name: 'database',
          directory: 'apps/backend'
        )
      end

      it 'returns flattened path with dashes' do
        expect(manifest_file.resource_name).to eq('apps-backend-database')
      end
    end

    context 'when relative path has complex structure' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/microservices/auth/user-service.yaml',
          relative_path: 'microservices/auth/user-service.yaml',
          service_name: 'user-service',
          directory: 'microservices/auth'
        )
      end

      it 'correctly flattens complex paths' do
        expect(manifest_file.resource_name).to eq('microservices-auth-user-service')
      end
    end
  end

  describe '#target_path' do
    context 'when file is in root directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/service.yaml',
          relative_path: 'service.yaml',
          service_name: 'service',
          directory: '.'
        )
      end

      it 'returns the service name' do
        expect(manifest_file.target_path).to eq('service')
      end
    end

    context 'when file is in subdirectory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/services/api.yaml',
          relative_path: 'services/api.yaml',
          service_name: 'api',
          directory: 'services'
        )
      end

      it 'returns the directory path' do
        expect(manifest_file.target_path).to eq('services')
      end
    end

    context 'when file is in deeply nested directory' do
      let(:manifest_file) do
        described_class.new(
          path: '/path/to/develop/apps/backend/database.yaml',
          relative_path: 'apps/backend/database.yaml',
          service_name: 'database',
          directory: 'apps/backend'
        )
      end

      it 'returns the full directory path' do
        expect(manifest_file.target_path).to eq('apps/backend')
      end
    end
  end

  describe 'edge cases and error conditions' do
    it 'handles files without extensions' do
      manifest_file = described_class.from_path('/path/to/develop/services/config', '/path/to/develop')
      
      expect(manifest_file.service_name).to eq('config')
      expect(manifest_file.relative_path).to eq('services/config')
    end

    it 'handles files with multiple dots in name' do
      manifest_file = described_class.from_path('/path/to/develop/app.config.yaml', '/path/to/develop')
      
      expect(manifest_file.service_name).to eq('app.config')
      expect(manifest_file.relative_path).to eq('app.config.yaml')
    end

    it 'handles empty directory names' do
      manifest_file = described_class.new(
        path: '/path/to/develop/service.yaml',
        relative_path: 'service.yaml',
        service_name: 'service',
        directory: ''
      )
      
      expect(manifest_file.in_subdirectory?).to be false
      expect(manifest_file.target_path).to eq('service')
      expect(manifest_file.resource_name).to eq('service')
    end

    it 'raises error when required attributes are missing' do
      expect {
        described_class.new(
          path: '/path/to/service.yaml'
          # missing required attributes
        )
      }.to raise_error(Dry::Struct::Error)
    end

    it 'raises error with invalid attribute types' do
      expect {
        described_class.new(
          path: 123, # should be string
          relative_path: 'service.yaml',
          service_name: 'service', 
          directory: '.'
        )
      }.to raise_error(Dry::Struct::Error)
    end
  end

  describe 'integration scenarios' do
    it 'handles typical Rails app structure' do
      manifest_file = described_class.from_path(
        '/projects/myapp/develop/services/web/rails-app.yaml', 
        '/projects/myapp/develop'
      )
      
      expect(manifest_file.service_name).to eq('rails-app')
      expect(manifest_file.directory).to eq('services/web')
      expect(manifest_file.resource_name).to eq('services-web-rails-app')
      expect(manifest_file.target_path).to eq('services/web')
      expect(manifest_file.in_subdirectory?).to be true
    end

    it 'handles microservices structure' do
      manifest_file = described_class.from_path(
        '/projects/microservices/production/backend/auth/user-auth-service.yaml',
        '/projects/microservices/production'
      )
      
      expect(manifest_file.service_name).to eq('user-auth-service')
      expect(manifest_file.directory).to eq('backend/auth')
      expect(manifest_file.resource_name).to eq('backend-auth-user-auth-service')
      expect(manifest_file.target_path).to eq('backend/auth')
      expect(manifest_file.in_subdirectory?).to be true
    end
  end
end