require 'spec_helper'

RSpec.describe Controllers::FluxGeneratorController do
  let(:generate_flux_manifests_use_case) { instance_double(UseCases::GenerateFluxManifests) }
  let(:setup_controller) { instance_double(Controllers::SetupController) }
  let(:controller) { described_class.new(generate_flux_manifests_use_case, setup_controller) }

  before do
    allow(controller).to receive(:puts)
  end

  describe '#initialize' do
    it 'accepts required dependencies' do
      expect(controller.instance_variable_get(:@generate_flux_manifests)).to eq(generate_flux_manifests_use_case)
      expect(controller.instance_variable_get(:@setup_controller)).to eq(setup_controller)
    end
  end

  describe '#generate_all' do
    let(:environments) { ['develop', 'staging'] }
    let(:repository_url) { 'https://github.com/example/repo' }

    before do
      allow(setup_controller).to receive(:setup_directories)
      allow(setup_controller).to receive(:setup_missing_directories)
      allow(setup_controller).to receive(:setup_missing_kustomizations)
      allow(generate_flux_manifests_use_case).to receive(:call)
    end

    context 'with provided repository URL' do
      it 'uses provided repository URL' do
        controller.generate_all(environments, repository_url)

        expect(generate_flux_manifests_use_case).to have_received(:call) do |envs, repo_url, resource_name, target_ns|
          expect(envs).to eq(environments)
          expect(repo_url).to eq(repository_url)
          expect(resource_name).to match(/^flux-[a-f0-9]{16}$/)
          expect(target_ns).to be_nil
        end
      end

      it 'runs setup sequence' do
        controller.generate_all(environments, repository_url)

        expect(setup_controller).to have_received(:setup_directories).with(environments)
        expect(setup_controller).to have_received(:setup_missing_directories)
        expect(setup_controller).to have_received(:setup_missing_kustomizations).with(environments)
      end

      it 'outputs configuration info' do
        controller.generate_all(environments, repository_url)

        expect(controller).to have_received(:puts).with('📋 Configured environments: develop,staging')
        expect(controller).to have_received(:puts).with('🔗 Repository URL: https://github.com/example/repo')
      end
    end

    context 'without repository URL' do
      it 'detects repository URL from environment' do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return('company/infrastructure')

        controller.generate_all(environments, nil)

        expect(generate_flux_manifests_use_case).to have_received(:call) do |envs, repo_url, resource_name, target_ns|
          expect(envs).to eq(environments)
          expect(repo_url).to eq('https://github.com/company/infrastructure')
          expect(resource_name).to match(/^flux-[a-f0-9]{16}$/)
          expect(target_ns).to be_nil
        end
      end

      it 'raises error when URL cannot be detected' do
        allow(ENV).to receive(:[]).and_return(nil)
        allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return(nil)

        expect {
          controller.generate_all(environments, nil)
        }.to raise_error(ArgumentError, 'Repository URL is required but not provided or detected')
      end
    end
  end

  describe 'private methods' do
    describe '#detect_repository_url' do
      it 'returns GitHub URL when GITHUB_REPOSITORY is set' do
        allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return('myorg/myrepo')

        result = controller.send(:detect_repository_url)

        expect(result).to eq('https://github.com/myorg/myrepo')
      end

      it 'returns nil when GITHUB_REPOSITORY is not set' do
        allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return(nil)

        result = controller.send(:detect_repository_url)

        expect(result).to be_nil
      end
    end
  end
end