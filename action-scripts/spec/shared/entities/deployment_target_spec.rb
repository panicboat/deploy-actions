require 'spec_helper'

RSpec.describe Entities::DeploymentTarget do
  let(:params) { { service: 'demo', stack: 'terragrunt', stack_id: 'aws', working_directory: 'dystopia/demo/aws' } }

  it 'exports five fixed fields with typed attributes and arbitrary captures' do
    target = described_class.new(**params, attributes: { 'token' => nil, 'enabled' => true, 'count' => 2 }, captures: { 'team' => 'platform' })
    expect(target.to_matrix_item).to eq(params.merge(environment: nil, token: nil, enabled: true, count: 2, team: 'platform'))
  end

  it 'expands service and arbitrary placeholders in common attributes' do
    attributes = { 'repository' => 'ghcr.io/{team}/{service}', 'tag' => '{service}-{service}' }
    target = described_class.new(**params, attributes: attributes, captures: { 'team' => 'payments' })
    expect(target.to_matrix_item).to include(repository: 'ghcr.io/payments/demo', tag: 'demo-demo', team: 'payments', environment: nil)
    expect(attributes).to eq('repository' => 'ghcr.io/{team}/{service}', 'tag' => '{service}-{service}')
  end

  it 'expands nested environment attributes without changing value types' do
    attributes = { 'settings' => { 'images' => ['ghcr.io/{team}/{service}:{environment}', 3, nil, false] }, 'enabled' => true }
    target = described_class.new(**params, environment: 'production', attributes: attributes, captures: { 'team' => 'payments' })
    expect(target.attributes).to eq('settings' => { 'images' => ['ghcr.io/payments/demo:production', 3, nil, false] }, 'enabled' => true)
    expect(attributes['settings']['images'].first).to eq('ghcr.io/{team}/{service}:{environment}')
  end

  it 'rejects unresolved attribute placeholders' do
    expect { described_class.new(**params, attributes: { 'repository' => 'ghcr.io/{team}/{service}' }) }.to raise_error(Entities::UnresolvedPlaceholderError, /team/)
    expect { described_class.new(**params, attributes: { 'tag' => '{environment}' }) }.to raise_error(Entities::UnresolvedPlaceholderError, /environment/)
  end

  it 'requires an explicit stack identity' do
    expect { described_class.new(**params.reject { |key, _| key == :stack_id }) }.to raise_error(ArgumentError, /stack_id/)
    expect { described_class.new(**params.merge(stack_id: '')) }.to raise_error(ArgumentError, /stack_id/)
  end

  %w[service environment stack stack_id working_directory].each do |key|
    it "rejects captures colliding with #{key}" do
      expect { described_class.new(**params, captures: { key => 'value' }) }.to raise_error(ArgumentError, /collides/)
    end
  end

  it 'rejects captures colliding with attributes' do
    expect { described_class.new(**params, attributes: { 'team' => 'a' }, captures: { 'team' => 'b' }) }.to raise_error(ArgumentError, /attributes/)
  end

  it 'uses service identity environment and directory for equality and hashing' do
    first = described_class.new(**params)
    second = described_class.new(**params, attributes: { 'region' => 'other' })
    expect(first).to eq(second)
    expect(first.hash).to eq(second.hash)
    expect([first, second].uniq.length).to eq(1)
    [{ stack_id: 'other' }, { service: 'api' }, { environment: 'develop' }, { working_directory: 'other/demo' }].each do |changes|
      expect(first).not_to eq(described_class.new(**params.merge(changes)))
    end
    expect(first).not_to eq(nil)
  end
end
