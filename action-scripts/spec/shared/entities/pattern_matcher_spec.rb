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

  describe '.extract' do
    it 'returns the captured value as a Hash on a full match' do
      expect(described_class.extract('{service}', 'api')).to eq('service' => 'api')
    end

    it 'returns all captures on a full match with multiple placeholders' do
      expect(
        described_class.extract('{team}/{service}/terragrunt/{environment}', 'payments/api/terragrunt/develop')
      ).to eq('team' => 'payments', 'service' => 'api', 'environment' => 'develop')
    end

    it 'returns nil when path has more segments than pattern' do
      expect(described_class.extract('{service}', 'api/extra')).to be_nil
    end

    it 'returns nil when path has fewer segments than pattern' do
      expect(described_class.extract('{a}/{b}', 'one')).to be_nil
    end

    it 'returns nil when a literal segment does not match' do
      expect(described_class.extract('a/{service}', 'b/c')).to be_nil
    end

    it 'returns an empty hash when the pattern has no placeholders and matches' do
      expect(described_class.extract('static', 'static')).to eq({})
    end

    it 'returns nil when a duplicate placeholder gets different values' do
      expect(described_class.extract('{a}/{a}', 'x/y')).to be_nil
    end

    it 'returns the single value when a duplicate placeholder gets the same value' do
      expect(described_class.extract('{a}/{a}', 'x/x')).to eq('a' => 'x')
    end

    it 'returns nil for nil pattern or path' do
      expect(described_class.extract(nil, 'x')).to be_nil
      expect(described_class.extract('{a}', nil)).to be_nil
    end
  end

  describe '.extract_prefix' do
    it 'matches the prefix and ignores additional segments' do
      result = described_class.extract_prefix(
        '{service}/terragrunt',
        'foo/terragrunt/develop/main.tf'
      )
      expect(result).to eq('service' => 'foo')
    end

    it 'matches when path equals the pattern exactly' do
      expect(
        described_class.extract_prefix('{service}/terragrunt', 'foo/terragrunt')
      ).to eq('service' => 'foo')
    end

    it 'returns nil when the path is shorter than the pattern' do
      expect(described_class.extract_prefix('{a}/{b}/c', 'x/y')).to be_nil
    end

    it 'returns nil when a literal segment does not match' do
      expect(described_class.extract_prefix('a/{b}', 'x/y/z')).to be_nil
    end

    it 'returns an empty hash when the pattern has no placeholders and the prefix matches' do
      expect(described_class.extract_prefix('static', 'static/sub/path')).to eq({})
    end

    it 'returns nil for nil pattern or path' do
      expect(described_class.extract_prefix(nil, 'x')).to be_nil
      expect(described_class.extract_prefix('{a}', nil)).to be_nil
    end
  end
end
