require 'spec_helper'

RSpec.describe Entities::Environment do
  describe '.from_name' do
    it 'creates an environment from name' do
      env = described_class.from_name('develop')

      expect(env.name).to eq('develop')
      expect(env.path).to eq('./develop')
      expect(env.cluster_path).to eq('./clusters/develop')
    end
  end

  describe '#flux_system_path' do
    it 'returns correct flux-system path' do
      env = described_class.from_name('staging')

      expect(env.flux_system_path).to eq('./clusters/staging/flux-system')
    end
  end

  describe '#apps_path' do
    it 'returns correct apps path' do
      env = described_class.from_name('production')

      expect(env.apps_path).to eq('./clusters/production/apps')
    end
  end

  describe '#valid?' do
    it 'returns true for valid environments' do
      %w[develop staging production].each do |env_name|
        env = described_class.from_name(env_name)
        expect(env.valid?).to be true
      end
    end

    it 'returns false for invalid environments' do
      env = described_class.from_name('invalid')
      expect(env.valid?).to be false
    end

    it 'returns false for empty name' do
      env = described_class.new(name: '', path: './', cluster_path: './clusters/')
      expect(env.valid?).to be false
    end
  end
end
