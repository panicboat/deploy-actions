require 'spec_helper'
require 'tempfile'

RSpec.describe UseCases::ConfigManagement::ValidateConfig do
  let(:file) { Tempfile.new(['workflow-config', '.yaml']) }
  let(:client) { Infrastructure::ConfigClient.new(config_path: file.path) }
  subject(:use_case) { described_class.new(config_client: client) }

  after { file.close! }

  it 'summarizes validated stacks and their environment union' do
    file.write(default_test_config)
    file.flush
    result = use_case.execute
    expect(result).to be_success
    expect(result.valid).to be(true)
    expect(result.config).to be_a(Entities::WorkflowConfig)
    expect(result.validation_summary).to include('stacks: 2', 'environments: 2')
  end

  it 'accepts configurations with only common stacks' do
    file.write({ 'stacks' => [{ 'name' => 'container', 'paths' => ['apps/{service}'], 'attributes' => {} }] }.to_yaml)
    file.flush
    expect(use_case.execute).to be_success
  end

  it 'validates inferred environments without requiring matching directories' do
    file.write({ 'stacks' => [{ 'name' => 'kubernetes', 'paths' => ['absent/{service}/{environment}'] }] }.to_yaml)
    file.flush
    result = use_case.execute
    expect(result).to be_success
    expect(result.validation_summary).to include('environments: 0')
  end

  it 'returns the original configuration error in validation errors' do
    file.write("stacks:\n  - name: container\n    paths: []\n")
    file.flush
    result = use_case.execute
    expect(result).to be_failure
    expect(result.validation_errors).to eq([result.error_message])
    expect(result.error_message).to include('stacks[0].paths')
  end

  it 'returns a failed result for missing files' do
    client = Infrastructure::ConfigClient.new(config_path: "#{file.path}.missing")
    result = described_class.new(config_client: client).execute
    expect(result).to be_failure
    expect(result.validation_errors.first).to include('.missing')
  end
end
