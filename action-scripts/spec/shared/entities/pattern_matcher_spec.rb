# spec/shared/entities/pattern_matcher_spec.rb

require 'spec_helper'

RSpec.describe Entities::PatternMatcher do
  describe '.placeholders' do
    it 'returns a single placeholder name' do
      expect(described_class.placeholders('{service}')).to eq(['service'])
    end

    it 'returns all placeholder names in left-to-right order' do
      expect(
        described_class.placeholders('{team}/{service}/terragrunt/{environment}')
      ).to eq(%w[team service environment])
    end

    it 'preserves duplicates' do
      expect(described_class.placeholders('{a}/{a}')).to eq(%w[a a])
    end

    it 'ignores uppercase names' do
      expect(described_class.placeholders('{Foo}')).to eq([])
    end

    it 'ignores hyphenated names' do
      expect(described_class.placeholders('{my-var}')).to eq([])
    end

    it 'ignores names with whitespace' do
      expect(described_class.placeholders('{a b}')).to eq([])
    end

    it 'returns empty for patterns with no placeholders' do
      expect(described_class.placeholders('static/path')).to eq([])
    end

    it 'returns empty for nil' do
      expect(described_class.placeholders(nil)).to eq([])
    end
  end
end
