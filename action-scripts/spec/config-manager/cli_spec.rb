require 'spec_helper'
require 'thor'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'ConfigManagerCLI' do
  before(:all) { load File.expand_path('../../config-manager/bin/config-manager', __dir__) }

  it 'does not start commands when loaded as a library' do
    expect(ConfigManagerCLI).not_to receive(:start)
    load File.expand_path('../../config-manager/bin/config-manager', __dir__)
  end

  it 'does not register service list or global exclusion commands' do
    expect(ConfigManagerCLI.all_commands.keys).not_to include('services', 'excluded_services')
  end

  it 'lists the union of configured environment names' do
    config = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [
      { 'id' => 'aws', 'path' => 'aws', 'environments' => { 'production' => {}, 'preview' => {} } },
      { 'id' => 'kubernetes', 'path' => 'k8s', 'environments' => { 'preview' => {}, 'sandbox' => {} } }
    ] }])
    client = instance_double(Infrastructure::ConfigClient, load_workflow_config: config)
    allow(ConfigManagerContainer).to receive(:resolve).with(:config_client).and_return(client)
    allow(ConfigManagerContainer).to receive(:resolve).with(:resolve_environments).and_return(UseCases::Shared::ResolveEnvironments.new(directory_scanner: Infrastructure::FileSystemClient.new))
    expect { ConfigManagerCLI.new.environments }.to output(/production.*preview.*sandbox/m).to_stdout
  end

  it 'lists environment names discovered from paths' do
    original = ENV['SOURCE_REPO_PATH']
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.git'))
      FileUtils.mkdir_p(File.join(root, 'apps/demo/preview'))
      ENV['SOURCE_REPO_PATH'] = root
      config = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }])
      client = instance_double(Infrastructure::ConfigClient, load_workflow_config: config)
      allow(ConfigManagerContainer).to receive(:resolve).with(:config_client).and_return(client)
      allow(ConfigManagerContainer).to receive(:resolve).with(:resolve_environments).and_return(UseCases::Shared::ResolveEnvironments.new(directory_scanner: Infrastructure::FileSystemClient.new))
      expect { ConfigManagerCLI.new.environments }.to output(/preview/).to_stdout
    end
  ensure
    ENV['SOURCE_REPO_PATH'] = original
  end

  it 'accepts a configuration file that uses YAML anchors' do
    Dir.mktmpdir do |root|
      File.write(File.join(root, 'workflow-config.yaml'), <<~YAML)
        profiles:
          base: &base
            region: ap-northeast-1
          copy: *base
      YAML
      Dir.chdir(root) do
        expect { expect { ConfigManagerCLI.new.check_file }.not_to raise_error }.to output(/File contains valid YAML/).to_stdout
      end
    end
  end

  it 'passes omitted environments to service diagnosis' do
    controller = instance_double(Interfaces::Controllers::ConfigManagerController)
    allow(ConfigManagerContainer).to receive(:resolve).with(:config_manager_controller).and_return(controller)
    expect(controller).to receive(:test_service_configuration).with(service_name: 'demo', environment: nil)
    ConfigManagerCLI.new.test('demo')
  end
end
