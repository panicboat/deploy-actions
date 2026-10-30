require 'spec_helper'

RSpec.describe Entities::DeploymentTarget do
  let(:params) { { service: 'demo', stack: 'aws', working_directory: 'dystopia/demo/aws' } }

  it 'exports four fixed fields with typed attributes and arbitrary captures' do
    target = described_class.new(**params, attributes: { 'token' => nil, 'enabled' => true, 'count' => 2 }, captures: { 'team' => 'platform' })
    expect(target.to_matrix_item).to eq(params.merge(environment: nil, token: nil, enabled: true, count: 2, team: 'platform'))
  end

  it 'emits the stack id as stack without stack_id' do
    target = described_class.new(service: 'api', stack: 'aws', working_directory: 'api/aws/develop', environment: 'develop')
    expect(target.to_matrix_item).to eq(service: 'api', environment: 'develop', stack: 'aws', working_directory: 'api/aws/develop')
  end

  it 'allows captures named stack_id' do
    expect { described_class.new(service: 'api', stack: 'aws', working_directory: 'd', captures: { 'stack_id' => 'x' }) }.not_to raise_error
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
    expect { described_class.new(**params.reject { |key, _| key == :stack }) }.to raise_error(ArgumentError, /stack/)
    expect { described_class.new(**params.merge(stack: '')) }.to raise_error(ArgumentError, /stack/)
  end

  %w[service environment stack working_directory].each do |key|
    it "rejects captures colliding with #{key}" do
      expect { described_class.new(**params, captures: { key => 'value' }) }.to raise_error(ArgumentError, /collides/)
    end
  end

  it 'rejects captures colliding with attributes' do
    expect { described_class.new(**params, attributes: { 'team' => 'a' }, captures: { 'team' => 'b' }) }.to raise_error(ArgumentError, /attributes/)
  end

  it 'uses service stack environment and directory for equality and hashing' do
    first = described_class.new(**params)
    second = described_class.new(**params, attributes: { 'region' => 'other' })
    expect(first).to eq(second)
    expect(first.hash).to eq(second.hash)
    expect([first, second].uniq.length).to eq(1)
    [{ stack: 'other' }, { service: 'api' }, { environment: 'develop' }, { working_directory: 'other/demo' }].each do |changes|
      expect(first).not_to eq(described_class.new(**params.merge(changes)))
    end
    expect(first).not_to eq(nil)
  end
end
