require 'spec_helper'

RSpec.describe Entities::TargetCandidate do
  def candidate(attributes: {}, exclude: [], captures: {})
    stack = Entities::Stack.new(id: 'aws', path: 'aws', paths: ['{service}/aws'], attributes: attributes, environments: nil, exclude: exclude)
    described_class.new(stack: stack, service: 'demo', environment: nil, working_directory: 'demo/aws', captures: captures)
  end

  describe '#to_listed_target' do
    it 'pairs the built target with its exclusion status' do
      listed = candidate(attributes: { 'repository' => 'ghcr.io/{service}' }, exclude: [{ 'service' => 'demo' }]).to_listed_target

      expect(listed.target.to_matrix_item).to eq(service: 'demo', environment: nil, stack: 'aws', working_directory: 'demo/aws', repository: 'ghcr.io/demo')
      expect(listed).to be_excluded
    end

    it 'is not excluded when no condition matches' do
      expect(candidate(exclude: [{ 'service' => 'other' }]).to_listed_target).not_to be_excluded
    end

    it 'raises for an attribute placeholder that has no value' do
      expect { candidate(attributes: { 'repository' => 'ghcr.io/{team}/{service}' }).to_listed_target }.to raise_error(Entities::UnresolvedPlaceholderError, /team/)
    end
  end
end
