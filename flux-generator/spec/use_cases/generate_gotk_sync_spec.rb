require 'spec_helper'

RSpec.describe UseCases::GenerateGotkSync do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:use_case) { described_class.new(file_system_repository) }

  before do
    allow(use_case).to receive(:puts)
  end

  describe '#initialize' do
    it 'accepts a file system repository dependency' do
      expect(use_case.instance_variable_get(:@file_system)).to eq(file_system_repository)
    end
  end

  describe '#call' do
    let(:environment) { Entities::Environment.from_name('develop') }
    let(:repository_url) { 'https://github.com/example/repo' }

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    it 'creates GitRepository resource with correct attributes' do
      allow(Entities::FluxResource).to receive(:git_repository).and_call_original
      
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(Entities::FluxResource).to have_received(:git_repository).with(
        name: 'test-resource',
        namespace: 'flux-system',
        url: repository_url
      )
    end

    it 'creates Kustomization resource with correct attributes' do
      allow(Entities::FluxResource).to receive(:kustomization).and_call_original
      
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(Entities::FluxResource).to have_received(:kustomization).with(
        name: 'test-resource',
        namespace: 'flux-system',
        path: environment.cluster_path,
        source_ref: {
          'kind' => 'GitRepository',
          'name' => 'test-resource'
        },
        interval: '10m0s'
      )
    end

    it 'writes combined YAML content to correct file path' do
      expected_file_path = "#{environment.flux_system_path}/gotk-sync.yaml"
      
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |path, content|
        expect(path).to eq(expected_file_path)
        expect(content).to include('apiVersion: source.toolkit.fluxcd.io/v1')
        expect(content).to include('kind: GitRepository')
        expect(content).to include('apiVersion: kustomize.toolkit.fluxcd.io/v1')
        expect(content).to include('kind: Kustomization')
        expect(content).to include('---')
      end
    end

    it 'generates YAML with correct repository URL' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include("url: #{repository_url}")
      end
    end

    it 'generates YAML with correct cluster path' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include("path: \"#{environment.cluster_path}\"")
      end
    end

    it 'outputs success message' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(use_case).to have_received(:puts).with("📝 Generated gotk-sync for #{environment.name}")
    end

    context 'with different environments' do
      let(:staging_environment) { Entities::Environment.from_name('staging') }
      let(:production_environment) { Entities::Environment.from_name('production') }

      it 'generates correct file paths for different environments' do
        use_case.call(staging_environment, repository_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/staging/flux-system/gotk-sync.yaml', anything)

        use_case.call(production_environment, repository_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/flux-system/gotk-sync.yaml', anything)
      end

      it 'generates correct cluster paths for different environments' do
        use_case.call(staging_environment, repository_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file).with(
          './clusters/staging/flux-system/gotk-sync.yaml',
          include('path: "./clusters/staging"')
        )

        use_case.call(production_environment, repository_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file).with(
          './clusters/production/flux-system/gotk-sync.yaml',
          include('path: "./clusters/production"')
        )
      end
    end

    context 'with different repository URLs' do
      let(:github_url) { 'https://github.com/company/infrastructure' }
      let(:gitlab_url) { 'https://gitlab.com/company/infrastructure' }

      it 'handles different repository URL formats' do
        use_case.call(environment, github_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file).with(
          './clusters/develop/flux-system/gotk-sync.yaml',
          include("url: #{github_url}")
        )

        use_case.call(environment, gitlab_url, 'test-resource')
        expect(file_system_repository).to have_received(:write_file).with(
          './clusters/develop/flux-system/gotk-sync.yaml', 
          include("url: #{gitlab_url}")
        )
      end
    end
  end

  describe 'YAML structure validation' do
    let(:environment) { Entities::Environment.from_name('develop') }
    let(:repository_url) { 'https://github.com/example/repo' }

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    it 'generates valid YAML structure' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        # Should contain two YAML documents separated by ---
        documents = content.split('---').reject(&:empty?).map(&:strip)
        expect(documents.size).to eq(2)
        
        # Each document should be valid YAML
        documents.each do |doc|
          expect { YAML.safe_load(doc) }.not_to raise_error
        end
      end
    end

    it 'includes GitRepository metadata' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include('name: test-resource')
        expect(content).to include('namespace: flux-system')
      end
    end

    it 'includes GitRepository spec' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include('interval: 1m0s')
        expect(content).to include('ref:')
        expect(content).to include('branch: main')
        expect(content).to include("url: #{repository_url}")
      end
    end

    it 'includes Kustomization metadata' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        # Should have three instances of test-resource name (GitRepo + Kustomization + sourceRef)
        expect(content.scan(/name: test-resource/).size).to eq(3)
        expect(content.scan(/namespace: flux-system/).size).to eq(2)
      end
    end

    it 'includes Kustomization spec' do
      use_case.call(environment, repository_url, 'test-resource')
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include('interval: 10m0s')
        expect(content).to include('prune: true')
        expect(content).to include('sourceRef:')
        expect(content).to include('  kind: GitRepository')
        expect(content).to include('  name: test-resource')
      end
    end
  end

  describe 'error handling' do
    let(:environment) { Entities::Environment.from_name('develop') }
    let(:repository_url) { 'https://github.com/example/repo' }

    it 'propagates file system repository errors' do
      allow(file_system_repository).to receive(:write_file)
        .and_raise(StandardError, 'File system error')
      
      expect {
        use_case.call(environment, repository_url, 'test-resource')
      }.to raise_error(StandardError, 'File system error')
    end

    it 'propagates FluxResource creation errors' do
      allow(Entities::FluxResource).to receive(:git_repository)
        .and_raise(Dry::Struct::Error, 'Invalid attributes')
      
      expect {
        use_case.call(environment, repository_url, 'test-resource')
      }.to raise_error(Dry::Struct::Error, 'Invalid attributes')
    end

    it 'handles YAML generation errors' do
      git_repo = instance_double(Entities::FluxResource)
      allow(git_repo).to receive(:to_yaml).and_raise(StandardError, 'YAML generation error')
      allow(Entities::FluxResource).to receive(:git_repository).and_return(git_repo)
      
      expect {
        use_case.call(environment, repository_url, 'test-resource')
      }.to raise_error(StandardError, 'YAML generation error')
    end
  end

  describe 'private methods' do
    describe '#file_system' do
      it 'provides access to the file system repository' do
        expect(use_case.send(:file_system)).to eq(file_system_repository)
      end
    end
  end

  describe 'integration scenarios' do
    let(:repository_url) { 'https://github.com/mycompany/k8s-infrastructure' }

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    context 'with typical production setup' do
      let(:environment) { Entities::Environment.from_name('production') }

      it 'generates production-ready gotk-sync manifest' do
        use_case.call(environment, repository_url, 'test-resource')

        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/flux-system/gotk-sync.yaml', anything)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          # Verify production-specific content
          expect(content).to include('path: "./clusters/production"')
          expect(content).to include(repository_url)
          expect(content).to include('interval: 10m0s')
          
          # Verify structure
          documents = content.split('---').reject(&:empty?).map(&:strip)
          expect(documents.size).to eq(2)
          
          # Parse and validate each document
          git_repo_yaml = YAML.safe_load(documents[0])
          kustomization_yaml = YAML.safe_load(documents[1])
          
          expect(git_repo_yaml['kind']).to eq('GitRepository')
          expect(kustomization_yaml['kind']).to eq('Kustomization')
        end

        expect(use_case).to have_received(:puts).with('📝 Generated gotk-sync for production')
      end
    end

    context 'with enterprise Git repository' do
      let(:environment) { Entities::Environment.from_name('develop') }
      let(:enterprise_url) { 'https://git.enterprise.com/infrastructure/k8s-manifests' }

      it 'handles enterprise repository URLs correctly' do
        use_case.call(environment, enterprise_url, 'test-resource')

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          expect(content).to include("url: #{enterprise_url}")
          
          # Verify the URL is properly quoted in YAML
          documents = content.split('---').reject(&:empty?).map(&:strip)
          parsed_content = YAML.safe_load(documents[0])
          expect(parsed_content['spec']['url']).to eq(enterprise_url)
        end
      end
    end
  end

  describe 'content structure verification' do
    let(:environment) { Entities::Environment.from_name('staging') }
    let(:repository_url) { 'https://github.com/test/repo' }

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    it 'creates properly structured multi-document YAML' do
      use_case.call(environment, repository_url, 'test-resource')

      expect(file_system_repository).to have_received(:write_file) do |_, content|
        # Split into documents
        documents = content.split('---').reject(&:empty?).map(&:strip)
        expect(documents.size).to eq(2)

        # Parse first document (GitRepository)
        git_repo = YAML.safe_load(documents[0])
        expect(git_repo['apiVersion']).to eq('source.toolkit.fluxcd.io/v1')
        expect(git_repo['kind']).to eq('GitRepository')
        expect(git_repo['metadata']['name']).to eq('test-resource')
        expect(git_repo['metadata']['namespace']).to eq('flux-system')
        expect(git_repo['spec']['url']).to eq(repository_url)
        expect(git_repo['spec']['ref']['branch']).to eq('main')
        expect(git_repo['spec']['interval']).to eq('1m0s')

        # Parse second document (Kustomization)
        kustomization = YAML.safe_load(documents[1])
        expect(kustomization['apiVersion']).to eq('kustomize.toolkit.fluxcd.io/v1')
        expect(kustomization['kind']).to eq('Kustomization')
        expect(kustomization['metadata']['name']).to eq('test-resource')
        expect(kustomization['metadata']['namespace']).to eq('flux-system')
        expect(kustomization['spec']['path']).to eq('./clusters/staging')
        expect(kustomization['spec']['interval']).to eq('10m0s')
        expect(kustomization['spec']['prune']).to be true
        expect(kustomization['spec']['sourceRef']['kind']).to eq('GitRepository')
        expect(kustomization['spec']['sourceRef']['name']).to eq('test-resource')
      end
    end
  end
end