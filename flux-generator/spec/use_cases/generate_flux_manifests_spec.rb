require 'spec_helper'

RSpec.describe UseCases::GenerateFluxManifests do
  let(:generate_gotk_sync) { instance_double(UseCases::GenerateGotkSync) }
  let(:generate_flux_system_kustomization) { instance_double(UseCases::GenerateFluxSystemKustomization) }
  let(:generate_apps_kustomization) { instance_double(UseCases::GenerateAppsKustomization) }
  let(:generate_app_resources) { instance_double(UseCases::GenerateAppResources) }
  let(:generate_environment_kustomizations) { instance_double(UseCases::GenerateEnvironmentKustomizations) }

  let(:use_case) do
    described_class.new(
      generate_gotk_sync,
      generate_flux_system_kustomization,
      generate_apps_kustomization,
      generate_app_resources,
      generate_environment_kustomizations
    )
  end

  before do
    allow(use_case).to receive(:puts)
  end

  describe '#initialize' do
    it 'accepts all required dependencies' do
      expect(use_case.instance_variable_get(:@generate_gotk_sync)).to eq(generate_gotk_sync)
      expect(use_case.instance_variable_get(:@generate_flux_system_kustomization)).to eq(generate_flux_system_kustomization)
      expect(use_case.instance_variable_get(:@generate_apps_kustomization)).to eq(generate_apps_kustomization)
      expect(use_case.instance_variable_get(:@generate_app_resources)).to eq(generate_app_resources)
      expect(use_case.instance_variable_get(:@generate_environment_kustomizations)).to eq(generate_environment_kustomizations)
    end
  end

  describe '#call' do
    let(:repository_url) { 'https://github.com/example/repo' }

    before do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_flux_system_kustomization).to receive(:call)
      allow(generate_apps_kustomization).to receive(:call)
      allow(generate_app_resources).to receive(:call)
      allow(generate_environment_kustomizations).to receive(:call)
    end

    context 'with single valid environment' do
      let(:environments) { ['develop'] }

      it 'generates manifests for valid environment' do
        use_case.call(environments, repository_url)

        expect(use_case).to have_received(:puts).with('🚀 Generating FluxCD manifests for develop...')
        expect(use_case).to have_received(:puts).with('✅ Generated FluxCD manifests for develop')
        expect(use_case).to have_received(:puts).with('🎉 FluxCD manifests generation completed!')
      end

      it 'calls all generation use cases in correct order' do
        environment = Entities::Environment.from_name('develop')

        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).to have_received(:call).with(environment, repository_url)
        expect(generate_flux_system_kustomization).to have_received(:call).with(environment)
        expect(generate_apps_kustomization).to have_received(:call).with(environment)
        expect(generate_app_resources).to have_received(:call).with(environment)
        expect(generate_environment_kustomizations).to have_received(:call).with(environment)
      end

      it 'creates Environment entity with correct attributes' do
        allow(Entities::Environment).to receive(:from_name).and_call_original

        use_case.call(environments, repository_url)

        expect(Entities::Environment).to have_received(:from_name).with('develop')
      end
    end

    context 'with multiple valid environments' do
      let(:environments) { ['develop', 'staging', 'production'] }

      it 'generates manifests for all valid environments' do
        use_case.call(environments, repository_url)

        expect(use_case).to have_received(:puts).with('🚀 Generating FluxCD manifests for develop...')
        expect(use_case).to have_received(:puts).with('✅ Generated FluxCD manifests for develop')
        expect(use_case).to have_received(:puts).with('🚀 Generating FluxCD manifests for staging...')
        expect(use_case).to have_received(:puts).with('✅ Generated FluxCD manifests for staging')
        expect(use_case).to have_received(:puts).with('🚀 Generating FluxCD manifests for production...')
        expect(use_case).to have_received(:puts).with('✅ Generated FluxCD manifests for production')
        expect(use_case).to have_received(:puts).with('🎉 FluxCD manifests generation completed!')
      end

      it 'calls generation use cases for each environment' do
        develop_env = Entities::Environment.from_name('develop')
        staging_env = Entities::Environment.from_name('staging')
        production_env = Entities::Environment.from_name('production')

        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).to have_received(:call).with(develop_env, repository_url)
        expect(generate_gotk_sync).to have_received(:call).with(staging_env, repository_url)
        expect(generate_gotk_sync).to have_received(:call).with(production_env, repository_url)

        expect(generate_flux_system_kustomization).to have_received(:call).with(develop_env)
        expect(generate_flux_system_kustomization).to have_received(:call).with(staging_env)
        expect(generate_flux_system_kustomization).to have_received(:call).with(production_env)

        expect(generate_apps_kustomization).to have_received(:call).with(develop_env)
        expect(generate_apps_kustomization).to have_received(:call).with(staging_env)
        expect(generate_apps_kustomization).to have_received(:call).with(production_env)

        expect(generate_app_resources).to have_received(:call).with(develop_env)
        expect(generate_app_resources).to have_received(:call).with(staging_env)
        expect(generate_app_resources).to have_received(:call).with(production_env)

        expect(generate_environment_kustomizations).to have_received(:call).with(develop_env)
        expect(generate_environment_kustomizations).to have_received(:call).with(staging_env)
        expect(generate_environment_kustomizations).to have_received(:call).with(production_env)
      end
    end

    context 'with invalid environments' do
      let(:environments) { ['invalid', 'develop', 'bad-env'] }

      it 'skips invalid environments and shows error messages' do
        use_case.call(environments, repository_url)

        expect(use_case).to have_received(:puts).with('❌ Invalid environment: invalid')
        expect(use_case).to have_received(:puts).with('❌ Invalid environment: bad-env')
        expect(use_case).to have_received(:puts).with('🚀 Generating FluxCD manifests for develop...')
        expect(use_case).to have_received(:puts).with('✅ Generated FluxCD manifests for develop')
        expect(use_case).to have_received(:puts).with('🎉 FluxCD manifests generation completed!')
      end

      it 'does not call generation use cases for invalid environments' do
        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).to have_received(:call).once
        expect(generate_flux_system_kustomization).to have_received(:call).once
        expect(generate_apps_kustomization).to have_received(:call).once
        expect(generate_app_resources).to have_received(:call).once
        expect(generate_environment_kustomizations).to have_received(:call).once
      end
    end

    context 'with empty environments array' do
      let(:environments) { [] }

      it 'completes without processing any environments' do
        use_case.call(environments, repository_url)

        expect(use_case).to have_received(:puts).with('🎉 FluxCD manifests generation completed!')
        expect(generate_gotk_sync).not_to have_received(:call)
        expect(generate_flux_system_kustomization).not_to have_received(:call)
        expect(generate_apps_kustomization).not_to have_received(:call)
        expect(generate_app_resources).not_to have_received(:call)
        expect(generate_environment_kustomizations).not_to have_received(:call)
      end
    end

    context 'with only invalid environments' do
      let(:environments) { ['invalid', 'bad-env', 'nonexistent'] }

      it 'shows error messages for all invalid environments' do
        use_case.call(environments, repository_url)

        expect(use_case).to have_received(:puts).with('❌ Invalid environment: invalid')
        expect(use_case).to have_received(:puts).with('❌ Invalid environment: bad-env')
        expect(use_case).to have_received(:puts).with('❌ Invalid environment: nonexistent')
        expect(use_case).to have_received(:puts).with('🎉 FluxCD manifests generation completed!')
      end

      it 'does not call any generation use cases' do
        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).not_to have_received(:call)
        expect(generate_flux_system_kustomization).not_to have_received(:call)
        expect(generate_apps_kustomization).not_to have_received(:call)
        expect(generate_app_resources).not_to have_received(:call)
        expect(generate_environment_kustomizations).not_to have_received(:call)
      end
    end
  end

  describe 'error handling' do
    let(:environments) { ['develop'] }
    let(:repository_url) { 'https://github.com/example/repo' }

    before do
      allow(generate_flux_system_kustomization).to receive(:call)
      allow(generate_apps_kustomization).to receive(:call)
      allow(generate_app_resources).to receive(:call)
      allow(generate_environment_kustomizations).to receive(:call)
    end

    it 'propagates errors from generate_gotk_sync' do
      allow(generate_gotk_sync).to receive(:call).and_raise(StandardError, 'Gotk sync error')

      expect {
        use_case.call(environments, repository_url)
      }.to raise_error(StandardError, 'Gotk sync error')
    end

    it 'propagates errors from generate_flux_system_kustomization' do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_flux_system_kustomization).to receive(:call).and_raise(StandardError, 'System kustomization error')

      expect {
        use_case.call(environments, repository_url)
      }.to raise_error(StandardError, 'System kustomization error')
    end

    it 'propagates errors from generate_apps_kustomization' do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_apps_kustomization).to receive(:call).and_raise(StandardError, 'Apps kustomization error')

      expect {
        use_case.call(environments, repository_url)
      }.to raise_error(StandardError, 'Apps kustomization error')
    end

    it 'propagates errors from generate_app_resources' do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_app_resources).to receive(:call).and_raise(StandardError, 'App resources error')

      expect {
        use_case.call(environments, repository_url)
      }.to raise_error(StandardError, 'App resources error')
    end

    it 'propagates errors from generate_environment_kustomizations' do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_environment_kustomizations).to receive(:call).and_raise(StandardError, 'Environment kustomizations error')

      expect {
        use_case.call(environments, repository_url)
      }.to raise_error(StandardError, 'Environment kustomizations error')
    end
  end

  describe 'private methods' do
    it 'provides access to all dependencies via attr_reader' do
      expect(use_case.send(:generate_gotk_sync)).to eq(generate_gotk_sync)
      expect(use_case.send(:generate_flux_system_kustomization)).to eq(generate_flux_system_kustomization)
      expect(use_case.send(:generate_apps_kustomization)).to eq(generate_apps_kustomization)
      expect(use_case.send(:generate_app_resources)).to eq(generate_app_resources)
      expect(use_case.send(:generate_environment_kustomizations)).to eq(generate_environment_kustomizations)
    end
  end

  describe 'integration scenarios' do
    let(:repository_url) { 'https://github.com/mycompany/infrastructure' }

    before do
      allow(generate_gotk_sync).to receive(:call)
      allow(generate_flux_system_kustomization).to receive(:call)
      allow(generate_apps_kustomization).to receive(:call)
      allow(generate_app_resources).to receive(:call)
      allow(generate_environment_kustomizations).to receive(:call)
    end

    context 'with typical deployment environments' do
      let(:environments) { ['develop', 'staging', 'production'] }

      it 'processes all environments successfully' do
        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).to have_received(:call).exactly(3).times
        expect(generate_flux_system_kustomization).to have_received(:call).exactly(3).times
        expect(generate_apps_kustomization).to have_received(:call).exactly(3).times
        expect(generate_app_resources).to have_received(:call).exactly(3).times
        expect(generate_environment_kustomizations).to have_received(:call).exactly(3).times
      end
    end

    context 'with mixed valid and invalid environments' do
      let(:environments) { ['develop', 'invalid-env', 'production', 'test-env'] }

      it 'processes only valid environments' do
        use_case.call(environments, repository_url)

        expect(generate_gotk_sync).to have_received(:call).exactly(2).times
        expect(generate_flux_system_kustomization).to have_received(:call).exactly(2).times
        expect(generate_apps_kustomization).to have_received(:call).exactly(2).times
        expect(generate_app_resources).to have_received(:call).exactly(2).times
        expect(generate_environment_kustomizations).to have_received(:call).exactly(2).times

        expect(use_case).to have_received(:puts).with('❌ Invalid environment: invalid-env')
        expect(use_case).to have_received(:puts).with('❌ Invalid environment: test-env')
      end
    end
  end
end