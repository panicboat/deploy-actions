# spec/shared/entities/deploy_label_spec.rb

require 'spec_helper'

RSpec.describe Entities::DeployLabel do
  describe '#initialize' do
    context 'with valid service label' do
      subject(:label) { described_class.new('deploy:test-service') }

      it 'initializes with label string' do
        expect(label.label_string).to eq('deploy:test-service')
      end
    end

    context 'with deploy:all label' do
      subject(:label) { described_class.new('deploy:all') }

      it 'initializes with deploy:all label' do
        expect(label.label_string).to eq('deploy:all')
      end
    end

    context 'with invalid label format' do
      subject(:label) { described_class.new('invalid-label') }

      it 'initializes with invalid label' do
        expect(label.label_string).to eq('invalid-label')
      end
    end
  end

  describe '#valid?' do
    context 'with valid service label' do
      subject(:label) { described_class.new('deploy:test-service') }

      it 'returns true' do
        expect(label).to be_valid
      end
    end

    context 'with deploy:all label' do
      subject(:label) { described_class.new('deploy:all') }

      it 'returns true' do
        expect(label).to be_valid
      end
    end

    context 'with service name containing hyphens' do
      subject(:label) { described_class.new('deploy:my-service-name') }

      it 'returns true' do
        expect(label).to be_valid
      end
    end

    context 'with service name containing underscores' do
      subject(:label) { described_class.new('deploy:my_service_name') }

      it 'returns true' do
        expect(label).to be_valid
      end
    end

    context 'with service name containing numbers' do
      subject(:label) { described_class.new('deploy:service123') }

      it 'returns true' do
        expect(label).to be_valid
      end
    end

    context 'with invalid label format' do
      subject(:label) { described_class.new('invalid-label') }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end

    context 'with empty label' do
      subject(:label) { described_class.new('') }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end

    context 'with nil label' do
      subject(:label) { described_class.new(nil) }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end

    context 'with deploy prefix only' do
      subject(:label) { described_class.new('deploy:') }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end

    context 'with service name containing spaces' do
      subject(:label) { described_class.new('deploy:service name') }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end

    context 'with service name containing special characters' do
      subject(:label) { described_class.new('deploy:service@name') }

      it 'returns false' do
        expect(label).not_to be_valid
      end
    end
  end

  describe '#service_name' do
    context 'with valid service label' do
      subject(:label) { described_class.new('deploy:test-service') }

      it 'returns service name' do
        expect(label.service_name).to eq('test-service')
      end
    end

    context 'with deploy:all label' do
      subject(:label) { described_class.new('deploy:all') }

      it 'returns "all"' do
        expect(label.service_name).to eq('all')
      end
    end

    context 'with invalid label' do
      subject(:label) { described_class.new('invalid-label') }

      it 'returns nil' do
        expect(label.service_name).to be_nil
      end
    end

    context 'with complex service name' do
      subject(:label) { described_class.new('deploy:my-complex_service123') }

      it 'returns complex service name' do
        expect(label.service_name).to eq('my-complex_service123')
      end
    end
  end

  describe '#deploy_all?' do
    context 'with deploy:all label' do
      subject(:label) { described_class.new('deploy:all') }

      it 'returns true' do
        expect(label).to be_deploy_all
      end
    end

    context 'with service-specific label' do
      subject(:label) { described_class.new('deploy:test-service') }

      it 'returns false' do
        expect(label).not_to be_deploy_all
      end
    end

    context 'with invalid label' do
      subject(:label) { described_class.new('invalid-label') }

      it 'returns false' do
        expect(label).not_to be_deploy_all
      end
    end
  end

  describe '#to_s' do
    context 'with valid label' do
      subject(:label) { described_class.new('deploy:test-service') }

      it 'returns label string' do
        expect(label.to_s).to eq('deploy:test-service')
      end
    end

    context 'with invalid label' do
      subject(:label) { described_class.new('invalid-label') }

      it 'returns original string' do
        expect(label.to_s).to eq('invalid-label')
      end
    end
  end

  describe '#==' do
    let(:label1) { described_class.new('deploy:test-service') }
    let(:label2) { described_class.new('deploy:test-service') }
    let(:label3) { described_class.new('deploy:other-service') }

    it 'returns true for equal labels' do
      expect(label1).to eq(label2)
    end

    it 'returns false for different labels' do
      expect(label1).not_to eq(label3)
    end

    it 'returns false when comparing with non-DeployLabel object' do
      expect(label1).not_to eq('deploy:test-service')
    end
  end

  describe '#hash' do
    let(:label1) { described_class.new('deploy:test-service') }
    let(:label2) { described_class.new('deploy:test-service') }

    it 'returns same hash for equal labels' do
      expect(label1.hash).to eq(label2.hash)
    end

    it 'allows labels to be used as hash keys' do
      hash = { label1 => 'value' }
      expect(hash[label2]).to eq('value')
    end
  end

  describe 'edge cases' do
    context 'with very long service name' do
      let(:long_name) { 'a' * 100 }
      subject(:label) { described_class.new("deploy:#{long_name}") }

      it 'handles long service names' do
        expect(label.service_name).to eq(long_name)
        expect(label).to be_valid
      end
    end

    context 'with minimum valid service name' do
      subject(:label) { described_class.new('deploy:a') }

      it 'handles single character service name' do
        expect(label.service_name).to eq('a')
        expect(label).to be_valid
      end
    end

    context 'with case sensitivity' do
      let(:label1) { described_class.new('deploy:Service') }
      let(:label2) { described_class.new('deploy:service') }

      it 'treats different cases as different labels' do
        expect(label1).not_to eq(label2)
        expect(label1.service_name).to eq('Service')
        expect(label2.service_name).to eq('service')
      end
    end
  end

  describe 'label pattern validation' do
    # Test various patterns that should be valid
    valid_patterns = [
      'deploy:simple',
      'deploy:with-hyphens',
      'deploy:with_underscores',
      'deploy:with123numbers',
      'deploy:mix-ed_patterns123',
      'deploy:all'
    ]

    valid_patterns.each do |pattern|
      context "with pattern '#{pattern}'" do
        subject(:label) { described_class.new(pattern) }

        it 'is considered valid' do
          expect(label).to be_valid
        end
      end
    end

    # Test various patterns that should be invalid
    invalid_patterns = [
      'deploy:',
      'deploy',
      'deploy: with-spaces',
      'deploy:with spaces',
      'deploy:with@special',
      'deploy:with.dots',
      'deploy:with/slashes',
      'deploy:with\\backslashes',
      'notdeploy:service',
      'deploy:service:extra',
      ''
    ]

    invalid_patterns.each do |pattern|
      context "with pattern '#{pattern}'" do
        subject(:label) { described_class.new(pattern) }

        it 'is considered invalid' do
          expect(label).not_to be_valid
        end
      end
    end
  end
end