# spec/shared/entities/result_spec.rb

require 'spec_helper'

RSpec.describe Entities::Result do
  describe '.success' do
    it 'carries the given value' do
      result = described_class.success(%w[a b])
      expect(result).to be_success
      expect(result).not_to be_failure
      expect(result.value).to eq(%w[a b])
      expect(result.error_message).to be_nil
    end

    it 'carries nil when no value is given' do
      result = described_class.success
      expect(result).to be_success
      expect(result.value).to be_nil
    end

    it 'carries the same value object' do
      value = Object.new
      expect(described_class.success(value).value).to be(value)
    end
  end

  describe '.failure' do
    it 'carries the error message' do
      result = described_class.failure('Something went wrong')
      expect(result).to be_failure
      expect(result).not_to be_success
      expect(result.error_message).to eq('Something went wrong')
      expect(result.value).to be_nil
    end

    [nil, '', '  '].each do |message|
      it "rejects #{message.inspect} as an error message" do
        expect { described_class.failure(message) }.to raise_error(ArgumentError, /error_message is required/)
      end
    end

    it 'requires an error message' do
      expect { described_class.failure }.to raise_error(ArgumentError)
    end
  end

  describe 'explicit interface' do
    subject(:result) { described_class.success(deploy_labels: ['deploy:api']) }

    it 'does not expose value keys as methods' do
      expect(result).not_to respond_to(:deploy_labels)
      expect { result.deploy_labels }.to raise_error(NoMethodError)
    end

    it 'does not expose a data accessor' do
      expect(result).not_to respond_to(:data)
    end

    it 'responds to its own interface' do
      expect(result).to respond_to(:success?, :failure?, :value, :error_message)
    end
  end

  describe 'immutability' do
    it 'freezes successful results' do
      result = described_class.success('value')
      expect(result).to be_frozen
      expect { result.instance_variable_set(:@success, false) }.to raise_error(FrozenError)
    end

    it 'freezes failed results' do
      expect(described_class.failure('Error')).to be_frozen
    end
  end
end
