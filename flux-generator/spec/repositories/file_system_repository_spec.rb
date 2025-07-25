require 'spec_helper'

RSpec.describe Repositories::FileSystemRepository do
  let(:repository) { described_class.new }

  describe '#ensure_directory' do
    let(:test_path) { '/tmp/test/flux/directory' }

    before do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(repository).to receive(:puts)
    end

    it 'creates directory when it does not exist' do
      repository.ensure_directory(test_path)
      
      expect(FileUtils).to have_received(:mkdir_p).with(test_path)
      expect(repository).to have_received(:puts).with("📦 Created directory: #{test_path}")
    end

    context 'when directory already exists' do
      before do
        allow(Dir).to receive(:exist?).with(test_path).and_return(true)
      end

      it 'does not create directory' do
        repository.ensure_directory(test_path)
        
        expect(FileUtils).not_to have_received(:mkdir_p)
        expect(repository).to have_received(:puts).with("📦 Created directory: #{test_path}")
      end
    end

    it 'handles nested directory paths' do
      nested_path = '/very/deep/nested/directory/structure'
      
      repository.ensure_directory(nested_path)
      
      expect(FileUtils).to have_received(:mkdir_p).with(nested_path)
    end

    it 'handles relative paths' do
      relative_path = './clusters/production/flux-system'
      
      repository.ensure_directory(relative_path)
      
      expect(FileUtils).to have_received(:mkdir_p).with(relative_path)
    end
  end

  describe '#write_file' do
    let(:file_path) { '/tmp/test/manifest.yaml' }
    let(:content) { "apiVersion: v1\nkind: Service\n" }
    let(:directory_path) { '/tmp/test' }

    before do
      allow(File).to receive(:dirname).with(file_path).and_return(directory_path)
      allow(repository).to receive(:ensure_directory)
      allow(File).to receive(:write)
      allow(repository).to receive(:puts)
    end

    it 'ensures parent directory exists' do
      repository.write_file(file_path, content)
      
      expect(repository).to have_received(:ensure_directory).with(directory_path)
    end

    it 'writes content to file' do
      repository.write_file(file_path, content)
      
      expect(File).to have_received(:write).with(file_path, content)
    end

    it 'outputs success message' do
      repository.write_file(file_path, content)
      
      expect(repository).to have_received(:puts).with("📝 Generated file: #{file_path}")
    end

    it 'handles complex YAML content' do
      complex_content = <<~YAML
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: flux-system
          namespace: flux-system
        spec:
          interval: 10m0s
          path: ./clusters/production
          prune: true
          sourceRef:
            kind: GitRepository
            name: flux-system
      YAML

      repository.write_file(file_path, complex_content)
      
      expect(File).to have_received(:write).with(file_path, complex_content)
    end

    it 'handles empty content' do
      repository.write_file(file_path, '')
      
      expect(File).to have_received(:write).with(file_path, '')
    end
  end

  describe '#directory_exists?' do
    let(:test_path) { '/tmp/test/directory' }

    it 'returns true when directory exists' do
      allow(Dir).to receive(:exist?).with(test_path).and_return(true)
      
      expect(repository.directory_exists?(test_path)).to be true
    end

    it 'returns false when directory does not exist' do
      allow(Dir).to receive(:exist?).with(test_path).and_return(false)
      
      expect(repository.directory_exists?(test_path)).to be false
    end

    it 'handles relative paths' do
      relative_path = './develop'
      allow(Dir).to receive(:exist?).with(relative_path).and_return(true)
      
      expect(repository.directory_exists?(relative_path)).to be true
    end

    it 'handles nested paths' do
      nested_path = '/projects/app/clusters/production/flux-system'
      allow(Dir).to receive(:exist?).with(nested_path).and_return(false)
      
      expect(repository.directory_exists?(nested_path)).to be false
    end
  end

  describe '#find_yaml_files' do
    let(:directory) { '/tmp/test/manifests' }

    context 'when directory exists' do
      before do
        allow(repository).to receive(:directory_exists?).with(directory).and_return(true)
      end

      it 'returns sorted YAML files' do
        yaml_files = [
          '/tmp/test/manifests/service2.yaml',
          '/tmp/test/manifests/service1.yaml',
          '/tmp/test/manifests/deployment.yaml'
        ]
        allow(Dir).to receive(:glob).with("#{directory}/**/*.yaml").and_return(yaml_files)
        
        result = repository.find_yaml_files(directory)
        
        expect(result).to eq([
          '/tmp/test/manifests/deployment.yaml',
          '/tmp/test/manifests/service1.yaml',
          '/tmp/test/manifests/service2.yaml'
        ])
      end

      it 'returns empty array when no YAML files found' do
        allow(Dir).to receive(:glob).with("#{directory}/**/*.yaml").and_return([])
        
        result = repository.find_yaml_files(directory)
        
        expect(result).to eq([])
      end

      it 'finds YAML files in nested directories' do
        yaml_files = [
          '/tmp/test/manifests/services/api.yaml',
          '/tmp/test/manifests/services/web.yaml',
          '/tmp/test/manifests/database/postgres.yaml'
        ]
        allow(Dir).to receive(:glob).with("#{directory}/**/*.yaml").and_return(yaml_files)
        
        result = repository.find_yaml_files(directory)
        
        expect(result).to include('/tmp/test/manifests/services/api.yaml')
        expect(result).to include('/tmp/test/manifests/services/web.yaml')
        expect(result).to include('/tmp/test/manifests/database/postgres.yaml')
      end

      it 'handles complex directory structures' do
        yaml_files = [
          '/tmp/test/manifests/backend/auth/user-service.yaml',
          '/tmp/test/manifests/backend/api/core-api.yaml',
          '/tmp/test/manifests/frontend/web-app.yaml',
          '/tmp/test/manifests/database/migrations/init.yaml'
        ]
        allow(Dir).to receive(:glob).with("#{directory}/**/*.yaml").and_return(yaml_files)
        
        result = repository.find_yaml_files(directory)
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(4)
        expect(result).to all(end_with('.yaml'))
      end
    end

    context 'when directory does not exist' do
      before do
        allow(repository).to receive(:directory_exists?).with(directory).and_return(false)
        allow(Dir).to receive(:glob)
      end

      it 'returns empty array' do
        result = repository.find_yaml_files(directory)
        
        expect(result).to eq([])
        expect(Dir).not_to have_received(:glob)
      end
    end

    it 'handles nil directory' do
      allow(repository).to receive(:directory_exists?).with(nil).and_return(false)
      
      result = repository.find_yaml_files(nil)
      
      expect(result).to eq([])
    end

    it 'handles empty string directory' do
      allow(repository).to receive(:directory_exists?).with('').and_return(false)
      
      result = repository.find_yaml_files('')
      
      expect(result).to eq([])
    end
  end

  describe '#relative_path' do
    it 'returns relative path from base path' do
      file_path = '/projects/myapp/develop/services/api.yaml'
      base_path = '/projects/myapp/develop'
      
      allow(Pathname).to receive(:new).with(file_path).and_return(
        double(relative_path_from: double(to_s: 'services/api.yaml'))
      )
      allow(Pathname).to receive(:new).with(base_path).and_return(double)
      
      result = repository.relative_path(file_path, base_path)
      
      expect(result).to eq('services/api.yaml')
    end

    it 'handles absolute paths correctly' do
      file_path = '/absolute/path/to/file.yaml'
      base_path = '/absolute/path'
      
      file_pathname = double
      base_pathname = double
      relative_pathname = double(to_s: 'to/file.yaml')
      
      allow(Pathname).to receive(:new).with(file_path).and_return(file_pathname)
      allow(Pathname).to receive(:new).with(base_path).and_return(base_pathname)
      allow(file_pathname).to receive(:relative_path_from).with(base_pathname).and_return(relative_pathname)
      
      result = repository.relative_path(file_path, base_path)
      
      expect(result).to eq('to/file.yaml')
    end

    it 'handles relative paths' do
      file_path = './develop/services/web.yaml'
      base_path = './develop'
      
      file_pathname = double
      base_pathname = double
      relative_pathname = double(to_s: 'services/web.yaml')
      
      allow(Pathname).to receive(:new).with(file_path).and_return(file_pathname)
      allow(Pathname).to receive(:new).with(base_path).and_return(base_pathname)
      allow(file_pathname).to receive(:relative_path_from).with(base_pathname).and_return(relative_pathname)
      
      result = repository.relative_path(file_path, base_path)
      
      expect(result).to eq('services/web.yaml')
    end

    it 'handles same directory files' do
      file_path = '/projects/app/service.yaml'
      base_path = '/projects/app'
      
      file_pathname = double
      base_pathname = double
      relative_pathname = double(to_s: 'service.yaml')
      
      allow(Pathname).to receive(:new).with(file_path).and_return(file_pathname)
      allow(Pathname).to receive(:new).with(base_path).and_return(base_pathname)
      allow(file_pathname).to receive(:relative_path_from).with(base_pathname).and_return(relative_pathname)
      
      result = repository.relative_path(file_path, base_path)
      
      expect(result).to eq('service.yaml')
    end

    it 'handles complex nested paths' do
      file_path = '/projects/microservices/develop/backend/auth/user-service.yaml'
      base_path = '/projects/microservices/develop'
      
      file_pathname = double
      base_pathname = double
      relative_pathname = double(to_s: 'backend/auth/user-service.yaml')
      
      allow(Pathname).to receive(:new).with(file_path).and_return(file_pathname)
      allow(Pathname).to receive(:new).with(base_path).and_return(base_pathname)
      allow(file_pathname).to receive(:relative_path_from).with(base_pathname).and_return(relative_pathname)
      
      result = repository.relative_path(file_path, base_path)
      
      expect(result).to eq('backend/auth/user-service.yaml')
    end
  end

  describe 'error conditions' do
    it 'handles FileUtils errors gracefully' do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, 'Permission denied')
      allow(repository).to receive(:puts)
      
      expect {
        repository.ensure_directory('/root/restricted')
      }.to raise_error(Errno::EACCES)
    end

    it 'handles File.write errors gracefully' do
      allow(repository).to receive(:ensure_directory)
      allow(File).to receive(:dirname).and_return('/tmp')
      allow(File).to receive(:write).and_raise(Errno::ENOSPC, 'No space left on device')
      allow(repository).to receive(:puts)
      
      expect {
        repository.write_file('/tmp/test.yaml', 'content')
      }.to raise_error(Errno::ENOSPC)
    end

    it 'handles Dir.glob errors gracefully' do
      allow(repository).to receive(:directory_exists?).and_return(true)
      allow(Dir).to receive(:glob).and_raise(Errno::EACCES, 'Permission denied')
      
      expect {
        repository.find_yaml_files('/restricted/directory')
      }.to raise_error(Errno::EACCES)
    end
  end
end