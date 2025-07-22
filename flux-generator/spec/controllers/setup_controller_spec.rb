require 'spec_helper'

RSpec.describe Controllers::SetupController do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:controller) { described_class.new(file_system_repository) }

  before do
    allow(controller).to receive(:puts)
    allow(file_system_repository).to receive(:ensure_directory)
    allow(file_system_repository).to receive(:directory_exists?).and_return(true)
    allow(file_system_repository).to receive(:write_file)
    allow(file_system_repository).to receive(:find_yaml_files).and_return([])
  end

  describe '#setup_directories' do
    let(:environment_names) { ['develop', 'staging'] }

    it 'sets up directories for all environments' do
      controller.setup_directories(environment_names)

      expect(file_system_repository).to have_received(:ensure_directory)
        .with('./clusters/develop/flux-system')
      expect(file_system_repository).to have_received(:ensure_directory)
        .with('./clusters/develop/apps')
      expect(file_system_repository).to have_received(:ensure_directory)
        .with('./clusters/staging/flux-system')
      expect(file_system_repository).to have_received(:ensure_directory)
        .with('./clusters/staging/apps')
    end

    it 'outputs setup message' do
      controller.setup_directories(environment_names)

      expect(controller).to have_received(:puts).with('🚀 Setting up FluxCD directories...')
    end
  end

  describe '#setup_missing_directories' do
    context 'when directories are missing' do
      before do
        allow(file_system_repository).to receive(:directory_exists?)
          .with('staging').and_return(false)
        allow(file_system_repository).to receive(:directory_exists?)
          .with('production').and_return(false)
      end

      it 'creates missing environment directories' do
        controller.setup_missing_directories

        expect(file_system_repository).to have_received(:ensure_directory).with('staging')
        expect(file_system_repository).to have_received(:ensure_directory).with('staging/services')
        expect(file_system_repository).to have_received(:ensure_directory).with('./clusters/staging/flux-system')
        expect(file_system_repository).to have_received(:ensure_directory).with('./clusters/staging/apps')

        expect(file_system_repository).to have_received(:ensure_directory).with('production')
        expect(file_system_repository).to have_received(:ensure_directory).with('production/services')
        expect(file_system_repository).to have_received(:ensure_directory).with('./clusters/production/flux-system')
        expect(file_system_repository).to have_received(:ensure_directory).with('./clusters/production/apps')
      end

      it 'creates placeholder kustomizations' do
        controller.setup_missing_directories

        expect(file_system_repository).to have_received(:write_file)
          .with('staging/kustomization.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('staging/services/kustomization.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('production/kustomization.yaml', anything)
        expect(file_system_repository).to have_received(:write_file)
          .with('production/services/kustomization.yaml', anything)
      end
    end

    context 'when all directories exist' do
      before do
        allow(file_system_repository).to receive(:directory_exists?)
          .and_return(true)
      end

      it 'does not create any directories' do
        allow(file_system_repository).to receive(:ensure_directory).and_call_original

        controller.setup_missing_directories

        expect(file_system_repository).not_to have_received(:ensure_directory)
      end
    end
  end

  describe '#setup_missing_kustomizations' do
    let(:environment_names) { ['develop'] }

    context 'when kustomization files are missing' do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end

      it 'creates missing root kustomization' do
        controller.setup_missing_kustomizations(environment_names)

        expect(file_system_repository).to have_received(:write_file)
          .with('develop/kustomization.yaml', anything)
      end

      it 'creates missing services kustomization when services directory exists' do
        allow(file_system_repository).to receive(:directory_exists?)
          .with('develop/services').and_return(true)

        controller.setup_missing_kustomizations(environment_names)

        expect(file_system_repository).to have_received(:write_file)
          .with('develop/services/kustomization.yaml', anything)
      end
    end

    context 'when kustomization files exist' do
      before do
        allow(File).to receive(:exist?).and_return(true)
      end

      it 'does not create existing kustomizations' do
        controller.setup_missing_kustomizations(environment_names)

        expect(file_system_repository).not_to have_received(:write_file)
      end
    end
  end
end