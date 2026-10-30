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
    allow(ConfigManagerContainer).to receive(:resolve).with(:resolve_environments).and_return(UseCases::Shared::ResolveEnvironments.new(directory_scanner: Infrastructure::DirectoryScanner.new(repository_root: Dir.pwd)))
    expect { ConfigManagerCLI.new.environments }.to output(/production.*preview.*sandbox/m).to_stdout
  end

  it 'lists environment names discovered from paths' do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'apps/demo/preview'))
      config = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }])
      client = instance_double(Infrastructure::ConfigClient, load_workflow_config: config)
      allow(ConfigManagerContainer).to receive(:resolve).with(:config_client).and_return(client)
      allow(ConfigManagerContainer).to receive(:resolve).with(:resolve_environments).and_return(UseCases::Shared::ResolveEnvironments.new(directory_scanner: Infrastructure::DirectoryScanner.new(repository_root: root)))
      expect { ConfigManagerCLI.new.environments }.to output(/preview/).to_stdout
    end
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
    expect(controller).to receive(:test_service_configuration).with(service_name: 'demo', environment: nil).and_return(Entities::Result.success)
    ConfigManagerCLI.new.test('demo')
  end

  {
    validate: [:validate_configuration, []],
    show: [:show_configuration, []],
    test: [:test_service_configuration, ['demo']],
    diagnostics: [:run_diagnostics, []],
    template: [:generate_config_template, []]
  }.each do |command, (action, args)|
    context "with the #{command} command" do
      let(:controller) { instance_double(Interfaces::Controllers::ConfigManagerController) }

      before { allow(ConfigManagerContainer).to receive(:resolve).with(:config_manager_controller).and_return(controller) }

      it 'exits 1 when the controller returns a failure Result' do
        allow(controller).to receive(action).and_return(Entities::Result.failure('boom'))
        expect { ConfigManagerCLI.new.public_send(command, *args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it 'does not exit when the controller returns a success Result' do
        allow(controller).to receive(action).and_return(Entities::Result.success)
        expect { ConfigManagerCLI.new.public_send(command, *args) }.not_to raise_error
      end
    end
  end
end
