require 'spec_helper'

RSpec.describe Entities::TargetCandidates do
  let(:stack) do
    Entities::Stack.new(
      id: 'aws', service_id: 'app', path: '{environment}', paths: ['teams/{team}/{service}/aws/{environment}'],
      attributes: { 'owner' => '{team}' }, environments: nil, exclude: [{ 'team' => 'sandbox' }]
    )
  end
  subject(:candidates) { described_class.new }

  def add(captures, directory: 'teams/a/demo/aws/develop')
    candidates.add(stack: stack, service: 'demo', environment: 'develop', working_directory: directory, captures: captures)
  end

  it 'merges candidates with the same identity and captures' do
    2.times { add({ 'team' => 'a', 'service' => 'demo', 'environment' => 'develop' }) }
    expect(candidates.to_a.length).to eq(1)
  end

  it 'rejects the same identity with different captures' do
    add({ 'team' => 'a' })
    expect { add({ 'product' => 'a' }) }.to raise_error(RuntimeError, /Conflicting captures for stack 'aws' at 'teams\/a\/demo\/aws\/develop'/)
  end

  it 'drops service and environment from captures' do
    add({ 'team' => 'a', 'service' => 'demo', 'environment' => 'develop' })
    expect(candidates.to_a.first.captures).to eq('team' => 'a')
  end

  it 'keeps the order of the first add' do
    add({ 'team' => 'b' }, directory: 'teams/b/demo/aws/develop')
    add({ 'team' => 'a' }, directory: 'teams/a/demo/aws/develop')
    add({ 'team' => 'b' }, directory: 'teams/b/demo/aws/develop')
    expect(candidates.to_a.map(&:working_directory)).to eq(%w[teams/b/demo/aws/develop teams/a/demo/aws/develop])
  end

  it 'judges exclusion from captures, service, and environment' do
    add({ 'team' => 'sandbox' }, directory: 'teams/sandbox/demo/aws/develop')
    add({ 'team' => 'a' })
    sandbox, kept = candidates.to_a
    expect(sandbox.exclusion_values).to eq('team' => 'sandbox', 'service' => 'demo', 'environment' => 'develop')
    expect([sandbox.excluded?, kept.excluded?]).to eq([true, false])
  end

  it 'builds a deployment target with the attributes of its environment' do
    add({ 'team' => 'a' })
    expect(candidates.to_a.first.to_deployment_target.to_matrix_item).to eq(
      service: 'demo', environment: 'develop', stack: 'aws', working_directory: 'teams/a/demo/aws/develop', owner: 'a', team: 'a'
    )
  end
end
