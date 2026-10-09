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
    config = Entities::WorkflowConfig.new('stacks' => [
      { 'name' => 'aws', 'paths' => ['{service}/aws'], 'environments' => { 'production' => {}, 'preview' => {} } },
      { 'name' => 'kubernetes', 'paths' => ['{service}/k8s'], 'environments' => { 'preview' => {}, 'sandbox' => {} } }
    ])
    client = instance_double(Infrastructure::ConfigClient, load_workflow_config: config)
    allow(ConfigManagerContainer).to receive(:resolve).with(:config_client).and_return(client)
    allow(ConfigManagerContainer).to receive(:resolve).with(:file_client).and_return(Infrastructure::FileSystemClient.new)
    expect { ConfigManagerCLI.new.environments }.to output(/production.*preview.*sandbox/m).to_stdout
  end

  it 'lists environment names discovered from paths' do
    original = ENV['SOURCE_REPO_PATH']
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, '.git'))
      FileUtils.mkdir_p(File.join(root, 'apps/demo/preview'))
      ENV['SOURCE_REPO_PATH'] = root
      config = Entities::WorkflowConfig.new('stacks' => [{ 'name' => 'kubernetes', 'paths' => ['apps/{service}/{environment}'] }])
      client = instance_double(Infrastructure::ConfigClient, load_workflow_config: config)
      allow(ConfigManagerContainer).to receive(:resolve).with(:config_client).and_return(client)
      allow(ConfigManagerContainer).to receive(:resolve).with(:file_client).and_return(Infrastructure::FileSystemClient.new)
      expect { ConfigManagerCLI.new.environments }.to output(/preview/).to_stdout
    end
  ensure
    ENV['SOURCE_REPO_PATH'] = original
  end

  it 'passes omitted environments to service diagnosis' do
    controller = instance_double(Interfaces::Controllers::ConfigManagerController)
    allow(ConfigManagerContainer).to receive(:resolve).with(:config_manager_controller).and_return(controller)
    expect(controller).to receive(:test_service_configuration).with(service_name: 'demo', environment: nil)
    ConfigManagerCLI.new.test('demo')
  end
end
