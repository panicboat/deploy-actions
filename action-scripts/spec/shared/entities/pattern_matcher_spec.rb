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

  describe '.expand' do
    it 'substitutes a single placeholder' do
      expect(described_class.expand('{service}', { 'service' => 'api' })).to eq('api')
    end

    it 'substitutes multiple placeholders' do
      result = described_class.expand(
        '{team}/{service}/terragrunt/{environment}',
        { 'team' => 'payments', 'service' => 'api', 'environment' => 'develop' }
      )
      expect(result).to eq('payments/api/terragrunt/develop')
    end

    it 'substitutes duplicate placeholders with the same value' do
      expect(described_class.expand('{a}/{a}', { 'a' => 'x' })).to eq('x/x')
    end

    it 'returns the pattern unchanged when it has no placeholders' do
      expect(described_class.expand('static/path', {})).to eq('static/path')
    end

    it 'raises UnresolvedPlaceholderError when a placeholder has no value' do
      expect {
        described_class.expand('{a}/{b}', { 'a' => 'x' })
      }.to raise_error(Entities::UnresolvedPlaceholderError, /b/)
    end

    it 'raises ArgumentError when a substituted value contains "/"' do
      expect {
        described_class.expand('{a}', { 'a' => 'x/y' })
      }.to raise_error(ArgumentError, %r{/})
    end

    it 'does not validate unused values' do
      expect(
        described_class.expand('{a}', { 'a' => 'x', 'unused' => 'has/slash' })
      ).to eq('x')
    end
  end
end
