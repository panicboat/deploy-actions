require 'spec_helper'

RSpec.describe UseCases::GenerateFluxSystemKustomization do
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

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    it 'creates kustomize config with gotk-sync.yaml resource' do
      allow(Entities::FluxResource).to receive(:kustomize_config).and_call_original
      
      use_case.call(environment)
      
      expect(Entities::FluxResource).to have_received(:kustomize_config).with(
        resources: ['gotk-sync.yaml']
      )
    end

    it 'writes YAML content to correct file path' do
      expected_file_path = "#{environment.flux_system_path}/kustomization.yaml"
      
      use_case.call(environment)
      
      expect(file_system_repository).to have_received(:write_file) do |path, content|
        expect(path).to eq(expected_file_path)
        expect(content).to include('apiVersion: kustomize.config.k8s.io/v1beta1')
        expect(content).to include('kind: Kustomization')
        expect(content).to include('resources:')
        expect(content).to include('- gotk-sync.yaml')
      end
    end

    it 'removes empty metadata from YAML content' do
      use_case.call(environment)
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).not_to include('metadata: {}')
        expect(content).not_to include('metadata:')
      end
    end

    it 'outputs success message' do
      use_case.call(environment)
      
      expect(use_case).to have_received(:puts).with("📝 Generated flux-system kustomization for #{environment.name}")
    end

    context 'with different environments' do
      let(:staging_environment) { Entities::Environment.from_name('staging') }
      let(:production_environment) { Entities::Environment.from_name('production') }

      it 'generates correct file paths for different environments' do
        use_case.call(staging_environment)
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/staging/flux-system/kustomization.yaml', anything)

        use_case.call(production_environment)
        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/flux-system/kustomization.yaml', anything)
      end
    end
  end

  describe 'YAML structure validation' do
    let(:environment) { Entities::Environment.from_name('develop') }

    before do
      allow(file_system_repository).to receive(:write_file)
    end

    it 'generates valid YAML structure' do
      use_case.call(environment)
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        parsed_yaml = YAML.safe_load(content)
        expect(parsed_yaml['apiVersion']).to eq('kustomize.config.k8s.io/v1beta1')
        expect(parsed_yaml['kind']).to eq('Kustomization')
        expect(parsed_yaml['resources']).to eq(['gotk-sync.yaml'])
        expect(parsed_yaml).not_to have_key('metadata')
      end
    end

    it 'creates clean kustomization without metadata' do
      use_case.call(environment)
      
      expect(file_system_repository).to have_received(:write_file) do |_, content|
        expect(content).to include('apiVersion: kustomize.config.k8s.io/v1beta1')
        expect(content).to include('kind: Kustomization')
        expect(content).to include('resources:')
        expect(content).to include('- gotk-sync.yaml')
        expect(content).not_to include('metadata')
        expect(content).not_to include('spec:')
      end
    end
  end

  describe 'error handling' do
    let(:environment) { Entities::Environment.from_name('develop') }

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

    it 'handles YAML generation errors' do
      kustomize_config = instance_double(Entities::FluxResource)
      allow(kustomize_config).to receive(:to_yaml).and_raise(StandardError, 'YAML generation error')
      allow(Entities::FluxResource).to receive(:kustomize_config).and_return(kustomize_config)
      
      expect {
        use_case.call(environment)
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
    before do
      allow(file_system_repository).to receive(:write_file)
    end

    context 'with production environment' do
      let(:environment) { Entities::Environment.from_name('production') }

      it 'generates production flux-system kustomization' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file)
          .with('./clusters/production/flux-system/kustomization.yaml', anything)

        expect(file_system_repository).to have_received(:write_file) do |_, content|
          parsed_yaml = YAML.safe_load(content)
          expect(parsed_yaml['resources']).to eq(['gotk-sync.yaml'])
          expect(parsed_yaml['kind']).to eq('Kustomization')
        end

        expect(use_case).to have_received(:puts).with('📝 Generated flux-system kustomization for production')
      end
    end

    context 'with all supported environments' do
      let(:environments) do
        ['develop', 'staging', 'production'].map { |name| Entities::Environment.from_name(name) }
      end

      it 'generates consistent kustomizations for all environments' do
        environments.each do |env|
          use_case.call(env)
        end

        expect(file_system_repository).to have_received(:write_file).exactly(3).times
        
        environments.each do |env|
          expect(file_system_repository).to have_received(:write_file)
            .with("#{env.flux_system_path}/kustomization.yaml", anything)
        end
      end
    end
  end
end