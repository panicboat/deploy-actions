require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::LabelResolver::DetermineTargetEnvironment do
  let(:config) { build(:workflow_config) }
  let(:client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  subject(:use_case) { described_class.new(config_client: client, file_client: Infrastructure::FileSystemClient.new) }

  [nil, []].each do |input|
    it "selects all declared environments for #{input.inspect}" do
      result = use_case.execute(target_environments: input)
      expect(result).to be_success
      expect(result.value).to eq(%w[develop production])
    end
  end

  it 'deduplicates requested environments preserving their order' do
    expect(use_case.execute(target_environments: %w[production production develop]).value).to eq(%w[production develop])
  end

  it 'rejects unknown environment names' do
    result = use_case.execute(target_environments: ['preview'])
    expect(result).to be_failure
    expect(result.error_message).to include('preview')
    expect(result.value).to be_nil
  end

  it 'selects no environment for a common-only configuration' do
    config = Entities::WorkflowConfig.new('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }])
    allow(client).to receive(:load_workflow_config).and_return(config)
    expect(use_case.execute(target_environments: nil).value).to eq([])
  end

  it 'accepts discovered environments and combines them with declared names' do
    original = ENV['SOURCE_REPO_PATH']
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.git'))
      FileUtils.mkdir_p(File.join(root, 'apps/demo/preview'))
      ENV['SOURCE_REPO_PATH'] = root
      discovered = Entities::WorkflowConfig.new('services' => [
        { 'id' => 'plain', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws', 'environments' => { 'production' => {} } }] },
        { 'id' => 'apps', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }
      ])
      allow(client).to receive(:load_workflow_config).and_return(discovered)
      expect(use_case.execute(target_environments: nil).value).to eq(%w[production preview])
      expect(use_case.execute(target_environments: ['preview']).value).to eq(['preview'])
      expect(use_case.execute(target_environments: ['unknown'])).to be_failure
    end
  ensure
    ENV['SOURCE_REPO_PATH'] = original
  end

  it 'propagates configuration errors as failures' do
    allow(client).to receive(:load_workflow_config).and_raise('invalid configuration')
    expect(use_case.execute(target_environments: []).error_message).to include('invalid configuration')
  end
end
