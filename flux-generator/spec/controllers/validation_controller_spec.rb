require 'spec_helper'

RSpec.describe Controllers::ValidationController do
  let(:file_system_repository) { instance_double(Repositories::FileSystemRepository) }
  let(:manifest_repository) { instance_double(Repositories::ManifestRepository) }
  let(:controller) { described_class.new(file_system_repository, manifest_repository) }

  before do
    allow(controller).to receive(:puts)
  end

  describe '#validate_environments' do
    let(:environment_names) { ['develop', 'staging'] }

    before do
      allow(file_system_repository).to receive(:directory_exists?).and_return(true)
      allow(manifest_repository).to receive(:find_manifests_for_environment).and_return([])
    end

    it 'validates each environment' do
      controller.validate_environments(environment_names)

      expect(controller).to have_received(:puts).with('  🔍 Checking environment: develop')
      expect(controller).to have_received(:puts).with('  🔍 Checking environment: staging')
    end

    context 'with valid environments' do
      before do
        allow(file_system_repository).to receive(:directory_exists?).and_return(true)
      end

      it 'shows success messages for existing directories' do
        controller.validate_environments(['develop'])

        expect(controller).to have_received(:puts).with('    ✅ Environment directory exists: develop')
        expect(controller).to have_received(:puts).with('    ✅ flux-system directory exists')
        expect(controller).to have_received(:puts).with('    ✅ apps directory exists')
      end
    end

    context 'with custom environment names' do
      it 'validates custom environment names successfully' do
        controller.validate_environments(['custom-env'])

        expect(controller).to have_received(:puts).with('  🔍 Checking environment: custom-env')
        expect(controller).to have_received(:puts).with('    ✅ Environment directory exists: custom-env')
        expect(controller).to have_received(:puts).with('    ✅ flux-system directory exists')
        expect(controller).to have_received(:puts).with('    ✅ apps directory exists')
      end
    end

    context 'with missing directories' do
      before do
        allow(file_system_repository).to receive(:directory_exists?)
          .with('develop').and_return(false)
        allow(file_system_repository).to receive(:directory_exists?)
          .with('./clusters/develop/flux-system').and_return(false)
        allow(file_system_repository).to receive(:directory_exists?)
          .with('./clusters/develop/apps').and_return(false)
      end

      it 'shows warnings for missing directories' do
        controller.validate_environments(['develop'])

        expect(controller).to have_received(:puts).with('    ⚠️  Environment directory missing: develop')
        expect(controller).to have_received(:puts).with('    ❌ Missing flux-system directory: ./clusters/develop/flux-system')
        expect(controller).to have_received(:puts).with('    ❌ Missing apps directory: ./clusters/develop/apps')
      end
    end

    context 'with manifests' do
      let(:manifest1) do
        instance_double(Entities::ManifestFile,
          relative_path: 'web-service.yaml',
          service_name: 'web-service'
        )
      end

      let(:manifest2) do
        instance_double(Entities::ManifestFile,
          relative_path: 'services/api.yaml',
          service_name: 'api'
        )
      end

      before do
        allow(manifest_repository).to receive(:find_manifests_for_environment)
          .and_return([manifest1, manifest2])
      end

      it 'shows manifest information' do
        controller.validate_environments(['develop'])

        expect(controller).to have_received(:puts).with('    📄 Found 2 manifest(s)')
        expect(controller).to have_received(:puts).with('      - web-service.yaml (web-service)')
        expect(controller).to have_received(:puts).with('      - services/api.yaml (api)')
      end
    end
  end
end