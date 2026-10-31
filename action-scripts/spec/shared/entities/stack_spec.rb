require 'spec_helper'

RSpec.describe Entities::Stack do
  def stack(path: 'aws/{environment}', attributes: {}, environments: nil, exclude: [])
    described_class.new(
      id: 'aws', path: path, paths: ["apps/{service}/#{path}"],
      attributes: attributes, environments: environments, exclude: exclude
    )
  end

  let(:declared) { stack(path: 'aws', environments: { 'develop' => { 'region' => 'a' }, 'production' => { 'region' => 'b' } }) }
  let(:common) { stack(path: '', attributes: { 'type' => 'container' }) }
  let(:discovered) { stack(path: 'overlays/{environment}', attributes: { 'type' => 'kustomize' }) }

  it 'freezes its collections' do
    expect(declared).to be_frozen
    expect(declared.paths).to be_frozen
    expect(declared.environments).to be_frozen
    expect(declared.environments.fetch('develop')).to be_frozen
    expect(declared.exclude).to be_frozen
  end

  it 'does not freeze the given collections' do
    attributes = { 'tags' => ['a'] }
    stack(attributes: attributes)
    expect(attributes).not_to be_frozen
    expect(attributes.fetch('tags')).not_to be_frozen
  end

  it 'keeps a value shared between attributes and environments as one object' do
    tags = ['a']
    built = stack(path: 'aws', attributes: { 'tags' => tags }, environments: { 'develop' => { 'tags' => tags } })
    expect(built.attributes.fetch('tags')).to be(built.environments.fetch('develop').fetch('tags'))
  end

  describe 'environment kinds' do
    it 'declares environments when environments are given' do
      expect(declared).to have_attributes(declares_environments?: true, discovers_environments?: false, common?: false)
      expect(declared.declared_environment_names).to eq(%w[develop production])
    end

    it 'is common without environments and without {environment} in the path' do
      expect(common).to have_attributes(declares_environments?: false, discovers_environments?: false, common?: true)
      expect(common.declared_environment_names).to eq([])
    end

    it 'discovers environments when only the path has {environment}' do
      expect(discovered).to have_attributes(declares_environments?: false, discovers_environments?: true, common?: false)
      expect(discovered.declared_environment_names).to eq([])
    end
  end

  describe '#target_environments' do
    it 'keeps the declared candidates in candidate order' do
      expect(declared.target_environments(%w[production develop])).to eq(%w[production develop])
      expect(declared.target_environments(%w[production preview])).to eq(%w[production])
    end

    it 'returns a single null environment for a common stack' do
      expect(common.target_environments(%w[production develop])).to eq([nil])
    end

    it 'returns the candidates as given for a discovering stack' do
      expect(discovered.target_environments(%w[production preview])).to eq(%w[production preview])
    end
  end

  describe '#target_attributes' do
    it 'returns the merged attributes of a declared environment' do
      expect(declared.target_attributes('production')).to eq('region' => 'b')
    end

    it 'rejects an environment the stack does not declare' do
      expect { declared.target_attributes('preview') }.to raise_error(KeyError)
    end

    it 'returns the stack attributes without declared environments' do
      expect(common.target_attributes(nil)).to eq('type' => 'container')
      expect(discovered.target_attributes('develop')).to eq('type' => 'kustomize')
    end
  end

  describe '#excluded?' do
    let(:excluding) { stack(exclude: [{ 'service' => 'demo', 'environment' => 'production' }, { 'team' => 'sandbox' }]) }

    it 'matches when every condition of any rule matches' do
      expect(excluding.excluded?('service' => 'demo', 'environment' => 'production')).to be(true)
      expect(excluding.excluded?('team' => 'sandbox', 'service' => 'api', 'environment' => 'develop')).to be(true)
    end

    it 'does not match when a condition differs or its key is absent' do
      expect(excluding.excluded?('service' => 'demo', 'environment' => 'develop')).to be(false)
      expect(excluding.excluded?('service' => 'demo')).to be(false)
    end

    it 'matches nothing without rules' do
      expect(stack.excluded?('service' => 'demo', 'environment' => 'production')).to be(false)
    end
  end
end
