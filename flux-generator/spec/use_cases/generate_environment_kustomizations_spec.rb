require 'spec_helper'

RSpec.describe UseCases::GenerateEnvironmentKustomizations do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:manifest_repository) { instance_double(Repositories::ManifestRepository) }
  let(:use_case) { described_class.new(file_system_repository, manifest_repository) }

  before do
    allow(use_case).to receive(:puts)
    allow(file_system_repository).to receive(:write_file)
  end

  describe '#call' do
    let(:environment) { Entities::Environment.from_name('develop') }

    context 'with manifests in subdirectories' do
      let(:manifests) do
        [
          instance_double(Entities::ManifestFile, directory: 'services', service_name: 'api'),
          instance_double(Entities::ManifestFile, directory: 'services', service_name: 'web'),
          instance_double(Entities::ManifestFile, directory: 'infrastructure', service_name: 'database')
        ]
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .and_return(manifests)
      end

      it 'generates root kustomization with subdirectories' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file) do |path, content|
          if path == 'develop/kustomization.yaml'
            expect(content).to include('- services/')
            expect(content).to include('- infrastructure/')
          end
        end
      end

      it 'generates service kustomizations for each directory' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file)
          .with('develop/services/kustomization.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('develop/infrastructure/kustomization.yaml', anything)
      end
    end

    context 'with only root level manifests' do
      let(:manifests) do
        [
          instance_double(Entities::ManifestFile, directory: '.', service_name: 'app1'),
          instance_double(Entities::ManifestFile, directory: '.', service_name: 'app2')
        ]
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .and_return(manifests)
      end

      it 'generates empty root kustomization' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file) do |path, content|
          if path == 'develop/kustomization.yaml'
            expect(content).to include('resources: []')
          end
        end
      end

      it 'does not generate service kustomizations' do
        use_case.call(environment)

        expect(file_system_repository).to have_received(:write_file).once
      end
    end
  end
end