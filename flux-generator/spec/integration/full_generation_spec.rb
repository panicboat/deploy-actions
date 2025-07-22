require 'spec_helper'

RSpec.describe 'Full Generation Integration' do
  let(:container) { FluxGeneratorContainer.configure }
  let(:controller) { container[:flux_generator_controller] }

  describe 'end-to-end flux generation' do
    it 'can access all dependencies through container' do
      expect(container[:file_system_repository]).to be_a(Repositories::FileSystemRepository)
      expect(container[:manifest_repository]).to be_a(Repositories::ManifestRepository)
      expect(container[:generate_flux_manifests]).to be_a(UseCases::GenerateFluxManifests)
      expect(container[:flux_generator_controller]).to be_a(Controllers::FluxGeneratorController)
    end

    it 'controller has proper dependencies injected' do
      expect(controller).to be_a(Controllers::FluxGeneratorController)
      expect(controller.instance_variable_get(:@generate_flux_manifests)).to be_a(UseCases::GenerateFluxManifests)
      expect(controller.instance_variable_get(:@setup_controller)).to be_a(Controllers::SetupController)
    end
  end

  describe 'dependency injection container' do
    it 'provides singleton instances' do
      container1 = FluxGeneratorContainer.configure
      container2 = FluxGeneratorContainer.configure
      
      expect(container1).to equal(container2)
    end

    it 'resolves dependencies by name' do
      file_system_repo = FluxGeneratorContainer.resolve(:file_system_repository)
      
      expect(file_system_repo).to be_a(Repositories::FileSystemRepository)
    end
  end
end