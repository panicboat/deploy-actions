require 'spec_helper'

RSpec.describe Entities::DeploymentTarget do
  let(:params) { { service: 'demo', stack: 'terragrunt', stack_id: 'aws', working_directory: 'dystopia/demo/aws' } }

  it 'exports five fixed fields with typed attributes and arbitrary captures' do
    target = described_class.new(**params, attributes: { 'token' => nil, 'enabled' => true, 'count' => 2 }, captures: { 'team' => 'platform' })
    expect(target.to_matrix_item).to eq(params.merge(environment: nil, token: nil, enabled: true, count: 2, team: 'platform'))
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
