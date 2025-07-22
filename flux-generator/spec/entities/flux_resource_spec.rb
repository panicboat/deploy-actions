require 'spec_helper'

RSpec.describe Entities::FluxResource do
  describe '#to_yaml' do
    context 'with kustomize.config.k8s.io resources' do
      let(:resource) do
        described_class.new(
          api_version: 'kustomize.config.k8s.io/v1beta1',
          kind: 'Kustomization',
          metadata: {},
          spec: { 'resources' => ['service1.yaml', 'service2.yaml'] }
        )
      end

      it 'places spec content at root level for kustomize.config.k8s.io' do
        yaml_output = resource.to_yaml
        
        expect(yaml_output).to include('apiVersion: kustomize.config.k8s.io/v1beta1')
        expect(yaml_output).to include('kind: Kustomization')
        expect(yaml_output).to include('resources:')
        expect(yaml_output).to include('- service1.yaml')
        expect(yaml_output).to include('- service2.yaml')
        expect(yaml_output).not_to include('spec:')
        expect(yaml_output).not_to include('metadata:')
      end
    end

    context 'with fluxcd.io resources' do
      let(:resource) do
        described_class.new(
          api_version: 'source.toolkit.fluxcd.io/v1',
          kind: 'GitRepository',
          metadata: { 'name' => 'flux-system', 'namespace' => 'flux-system' },
          spec: { 'url' => 'https://github.com/example/repo', 'interval' => '1m0s' }
        )
      end

      it 'places spec content under spec key for fluxcd.io' do
        yaml_output = resource.to_yaml
        
        expect(yaml_output).to include('apiVersion: source.toolkit.fluxcd.io/v1')
        expect(yaml_output).to include('kind: GitRepository')
        expect(yaml_output).to include('metadata:')
        expect(yaml_output).to include('  name: flux-system')
        expect(yaml_output).to include('  namespace: flux-system')
        expect(yaml_output).to include('spec:')
        expect(yaml_output).to include('  url: https://github.com/example/repo')
        expect(yaml_output).to include('  interval: 1m0s')
      end
    end

    context 'with empty metadata' do
      let(:resource) do
        described_class.new(
          api_version: 'kustomize.config.k8s.io/v1beta1',
          kind: 'Kustomization',
          metadata: {},
          spec: { 'resources' => [] }
        )
      end

      it 'omits metadata when empty' do
        yaml_output = resource.to_yaml
        
        expect(yaml_output).not_to include('metadata:')
      end
    end
  end

  describe '.git_repository' do
    context 'with default parameters' do
      let(:git_repo) do
        described_class.git_repository(
          name: 'flux-system',
          namespace: 'flux-system', 
          url: 'https://github.com/example/repo'
        )
      end

      it 'creates a GitRepository with correct structure' do
        expect(git_repo.api_version).to eq('source.toolkit.fluxcd.io/v1')
        expect(git_repo.kind).to eq('GitRepository')
        expect(git_repo.metadata).to eq({
          'name' => 'flux-system',
          'namespace' => 'flux-system'
        })
        expect(git_repo.spec).to eq({
          'interval' => '1m0s',
          'ref' => { 'branch' => 'main' },
          'url' => 'https://github.com/example/repo'
        })
      end

      it 'generates valid YAML' do
        yaml_output = git_repo.to_yaml
        
        expect(yaml_output).to include('apiVersion: source.toolkit.fluxcd.io/v1')
        expect(yaml_output).to include('kind: GitRepository')
        expect(yaml_output).to include('name: flux-system')
        expect(yaml_output).to include('namespace: flux-system')
        expect(yaml_output).to include('interval: 1m0s')
        expect(yaml_output).to include('branch: main')
        expect(yaml_output).to include('url: https://github.com/example/repo')
      end
    end

    context 'with custom parameters' do
      let(:git_repo) do
        described_class.git_repository(
          name: 'my-repo',
          namespace: 'custom-ns',
          url: 'https://github.com/custom/repo',
          branch: 'develop',
          interval: '5m0s'
        )
      end

      it 'creates a GitRepository with custom values' do
        expect(git_repo.metadata).to eq({
          'name' => 'my-repo',
          'namespace' => 'custom-ns'
        })
        expect(git_repo.spec).to eq({
          'interval' => '5m0s',
          'ref' => { 'branch' => 'develop' },
          'url' => 'https://github.com/custom/repo'
        })
      end
    end
  end

  describe '.kustomization' do
    context 'with minimum required parameters' do
      let(:kustomization) do
        described_class.kustomization(
          name: 'flux-system',
          namespace: 'flux-system',
          path: './clusters/production',
          source_ref: { 'kind' => 'GitRepository', 'name' => 'flux-system' }
        )
      end

      it 'creates a Kustomization with correct structure' do
        expect(kustomization.api_version).to eq('kustomize.toolkit.fluxcd.io/v1')
        expect(kustomization.kind).to eq('Kustomization')
        expect(kustomization.metadata).to eq({
          'name' => 'flux-system',
          'namespace' => 'flux-system'
        })
        expect(kustomization.spec).to eq({
          'interval' => '10m0s',
          'path' => './clusters/production',
          'prune' => true,
          'sourceRef' => { 'kind' => 'GitRepository', 'name' => 'flux-system' }
        })
      end

      it 'generates valid YAML' do
        yaml_output = kustomization.to_yaml
        
        expect(yaml_output).to include('apiVersion: kustomize.toolkit.fluxcd.io/v1')
        expect(yaml_output).to include('kind: Kustomization')
        expect(yaml_output).to include('name: flux-system')
        expect(yaml_output).to include('namespace: flux-system')
        expect(yaml_output).to include('interval: 10m0s')
        expect(yaml_output).to include('path: "./clusters/production"')
        expect(yaml_output).to include('prune: true')
        expect(yaml_output).to include('sourceRef:')
        expect(yaml_output).to include('  kind: GitRepository')
        expect(yaml_output).to include('  name: flux-system')
      end
    end

    context 'with all optional parameters' do
      let(:kustomization) do
        described_class.kustomization(
          name: 'apps',
          namespace: 'flux-system',
          path: './apps',
          source_ref: { 'kind' => 'GitRepository', 'name' => 'flux-system' },
          interval: '5m0s',
          prune: false,
          target_namespace: 'default',
          post_build: { 'substitute' => { 'cluster_name' => 'production' } }
        )
      end

      it 'creates a Kustomization with all parameters' do
        expect(kustomization.spec).to eq({
          'interval' => '5m0s',
          'path' => './apps',
          'prune' => false,
          'sourceRef' => { 'kind' => 'GitRepository', 'name' => 'flux-system' },
          'targetNamespace' => 'default',
          'postBuild' => { 'substitute' => { 'cluster_name' => 'production' } }
        })
      end

      it 'includes optional parameters in YAML' do
        yaml_output = kustomization.to_yaml
        
        expect(yaml_output).to include('interval: 5m0s')
        expect(yaml_output).to include('prune: false')
        expect(yaml_output).to include('targetNamespace: default')
        expect(yaml_output).to include('postBuild:')
        expect(yaml_output).to include('substitute:')
        expect(yaml_output).to include('cluster_name: production')
      end
    end

    context 'with nil optional parameters' do
      let(:kustomization) do
        described_class.kustomization(
          name: 'apps',
          namespace: 'flux-system',
          path: './apps',
          source_ref: { 'kind' => 'GitRepository', 'name' => 'flux-system' },
          target_namespace: nil,
          post_build: nil
        )
      end

      it 'omits nil optional parameters from spec' do
        expect(kustomization.spec).not_to have_key('targetNamespace')
        expect(kustomization.spec).not_to have_key('postBuild')
        expect(kustomization.spec).to have_key('interval')
        expect(kustomization.spec).to have_key('path')
        expect(kustomization.spec).to have_key('prune')
        expect(kustomization.spec).to have_key('sourceRef')
      end

      it 'omits nil parameters from YAML' do
        yaml_output = kustomization.to_yaml
        
        expect(yaml_output).not_to include('targetNamespace:')
        expect(yaml_output).not_to include('postBuild:')
      end
    end
  end

  describe '.kustomize_config' do
    context 'with resources' do
      let(:kustomize_config) do
        described_class.kustomize_config(
          resources: ['service1.yaml', 'service2.yaml', 'deployment.yaml']
        )
      end

      it 'creates a kustomize config with correct structure' do
        expect(kustomize_config.api_version).to eq('kustomize.config.k8s.io/v1beta1')
        expect(kustomize_config.kind).to eq('Kustomization')
        expect(kustomize_config.metadata).to eq({})
        expect(kustomize_config.spec).to eq({
          'resources' => ['service1.yaml', 'service2.yaml', 'deployment.yaml']
        })
      end

      it 'generates valid YAML without spec wrapper' do
        yaml_output = kustomize_config.to_yaml
        
        expect(yaml_output).to include('apiVersion: kustomize.config.k8s.io/v1beta1')
        expect(yaml_output).to include('kind: Kustomization')
        expect(yaml_output).to include('resources:')
        expect(yaml_output).to include('- service1.yaml')
        expect(yaml_output).to include('- service2.yaml')
        expect(yaml_output).to include('- deployment.yaml')
        expect(yaml_output).not_to include('spec:')
        expect(yaml_output).not_to include('metadata:')
      end
    end

    context 'with empty resources' do
      let(:kustomize_config) do
        described_class.kustomize_config(resources: [])
      end

      it 'creates a kustomize config with empty resources' do
        expect(kustomize_config.spec).to eq({ 'resources' => [] })
      end

      it 'generates valid YAML with empty resources' do
        yaml_output = kustomize_config.to_yaml
        
        expect(yaml_output).to include('resources: []')
      end
    end
  end

  describe 'error conditions' do
    it 'raises error when required attributes are missing' do
      expect {
        described_class.new(
          api_version: 'source.toolkit.fluxcd.io/v1',
          kind: 'GitRepository'
          # missing metadata and spec
        )
      }.to raise_error(Dry::Struct::Error)
    end

    it 'raises error with invalid attribute types' do
      expect {
        described_class.new(
          api_version: 123, # should be string
          kind: 'GitRepository',
          metadata: {},
          spec: {}
        )
      }.to raise_error(Dry::Struct::Error)
    end
  end
end