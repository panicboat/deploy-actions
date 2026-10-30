require 'spec_helper'
require 'tempfile'

RSpec.describe UseCases::ConfigManagement::ValidateConfig do
  let(:file) { Tempfile.new(['workflow-config', '.yaml']) }
  let(:client) { Infrastructure::ConfigClient.new(config_path: file.path) }
  subject(:use_case) { described_class.new(config_client: client) }

  after { file.close! }

  it 'summarizes validated services, stacks, and their environment union' do
    file.write(default_test_config)
    file.flush
    result = use_case.execute
    expect(result).to be_success
    expect(result.value).to be_a(UseCases::ConfigManagement::Validation)
    expect(result.value.config).to be_a(Entities::WorkflowConfig)
    expect(result.value.summary.lines.map(&:chomp)).to include('services: 1 configured', 'stacks: 2 configured', 'environments: 2 configured')
  end

  it 'accepts configurations with only common stacks' do
    file.write({ 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }] }.to_yaml)
    file.flush
    expect(use_case.execute).to be_success
  end

  it 'validates inferred environments without requiring matching directories' do
    file.write({ 'services' => [{ 'id' => 'app', 'roots' => ['absent/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }] }.to_yaml)
    file.flush
    result = use_case.execute
    expect(result).to be_success
    expect(result.value.summary).to include('environments: 0')
  end

  it 'returns the original configuration error as the failure message' do
    file.write("services:\n  - id: app\n    roots: []\n    stacks: []\n")
    file.flush
    result = use_case.execute
    expect(result).to be_failure
    expect(result.error_message).to include('services[0].roots')
  end

  it 'returns a failed result for missing files' do
    client = Infrastructure::ConfigClient.new(config_path: "#{file.path}.missing")
    result = described_class.new(config_client: client).execute
    expect(result).to be_failure
    expect(result.error_message).to include('.missing')
  end
end
