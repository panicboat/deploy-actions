require 'spec_helper'
require 'thor'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'ConfigManagerCLI' do
  let(:config_manager_path) { File.expand_path('../../config-manager/bin/config-manager', __dir__) }

  before(:all) { load File.expand_path('../../config-manager/bin/config-manager', __dir__) }

  it 'does not start commands when loaded as a library' do
    expect(ConfigManagerCLI).not_to receive(:start)
    load config_manager_path
  end

  it 'registers only the validate and test commands' do
    expect(ConfigManagerCLI.all_commands.keys - Thor.all_commands.keys).to contain_exactly('validate', 'test')
  end

  context 'with a controller' do
    let(:controller) { instance_double(Interfaces::Controllers::ConfigManagerController) }

    before { allow(ConfigManagerContainer).to receive(:resolve).with(:config_manager_controller).and_return(controller) }

    it 'passes the service and the environment to the controller' do
      expect(controller).to receive(:test_service).with(service_name: 'demo', environment: 'production').and_return(Entities::Result.success)
      ConfigManagerCLI.new.test('demo', 'production')
    end

    it 'passes an omitted environment as nil' do
      expect(controller).to receive(:test_service).with(service_name: 'demo', environment: nil).and_return(Entities::Result.success)
      ConfigManagerCLI.new.test('demo')
    end

    {
      validate: [:validate, []],
      test: [:test_service, ['demo']]
    }.each do |command, (action, args)|
      it "exits 1 when #{command} returns a failure Result" do
        allow(controller).to receive(action).and_return(Entities::Result.failure('boom'))
        expect { ConfigManagerCLI.new.public_send(command, *args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it "does not exit when #{command} returns a success Result" do
        allow(controller).to receive(action).and_return(Entities::Result.success)
        expect { ConfigManagerCLI.new.public_send(command, *args) }.not_to raise_error
      end
    end
  end

  context 'when run as a process' do
    around do |example|
      Dir.mktmpdir do |root|
        @root = root
        Open3.capture3('git', 'init', '--quiet', root)
        example.run
      end
    end

    def write_config(content)
      File.write(File.join(@root, 'workflow-config.yaml'), content)
    end

    def run_config_manager(*args, env: {})
      base_env = %w[GITHUB_ACTIONS GITHUB_OUTPUT GITHUB_ENV SOURCE_REPO_PATH WORKFLOW_CONFIG_PATH].to_h { |key| [key, nil] }
      Open3.capture3(base_env.merge(env), RbConfig.ruby, config_manager_path, *args, chdir: @root)
    end

    let(:valid_config) { { 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }] }.to_yaml }

    it 'exits 1 for test with a name that is not a valid service name' do
      write_config(valid_config)
      FileUtils.mkdir_p(File.join(@root, 'apps/a.b'))
      stdout, _stderr, status = run_config_manager('test', 'a.b')
      expect(status.exitstatus).to eq(1)
      expect(stdout).to include('Invalid service name: "a.b" (use a name matching [a-zA-Z0-9_-]+)')
      expect(stdout).not_to include('Service Configuration Test')
    end

    it 'exits 0 with an empty result for test with a valid name that matches no directory' do
      write_config(valid_config)
      stdout, stderr, status = run_config_manager('test', 'missing')
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to eq("Service Configuration Test\nService: missing\n")
    end

    it 'exits 1 when the configuration is invalid' do
      write_config("services: 1\n")
      stdout, _stderr, status = run_config_manager('validate')
      expect(status.exitstatus).to eq(1)
      expect(stdout).to include('Configuration validation failed')
    end

    it 'exits 0 when the configuration is valid' do
      write_config(valid_config)
      stdout, stderr, status = run_config_manager('validate')
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to include('Configuration is valid')
    end

    it 'writes no step outputs or environment variables when validating in GitHub Actions' do
      write_config(valid_config)
      output_path = File.join(@root, 'GITHUB_OUTPUT')
      env_path = File.join(@root, 'GITHUB_ENV')
      [output_path, env_path].each { |path| File.write(path, '') }
      _stdout, stderr, status = run_config_manager('validate', env: { 'GITHUB_ACTIONS' => 'true', 'GITHUB_OUTPUT' => output_path, 'GITHUB_ENV' => env_path })
      expect(status.exitstatus).to eq(0), stderr
      expect(File.read(output_path)).to eq('')
      expect(File.read(env_path)).to eq('')
    end

    it 'stops in GitHub Actions before validating when GITHUB_OUTPUT is not set' do
      write_config(valid_config)
      stdout, stderr, status = run_config_manager('validate', env: { 'GITHUB_ACTIONS' => 'true' })
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('GITHUB_OUTPUT is not set')
      expect(stdout).not_to include('Configuration is valid')
    end

    it 'validates outside a git checkout' do
      Dir.mktmpdir do |outside|
        config_path = File.join(outside, 'workflow-config.yaml')
        File.write(config_path, valid_config)
        stdout, stderr, status = Open3.capture3({ 'GITHUB_ACTIONS' => nil, 'GITHUB_OUTPUT' => nil, 'SOURCE_REPO_PATH' => nil, 'WORKFLOW_CONFIG_PATH' => config_path }, RbConfig.ruby, config_manager_path, 'validate', chdir: outside)
        expect(status.exitstatus).to eq(0), stderr
        expect(stdout).to include('Configuration is valid')
      end
    end

    it 'exits 1 when test is called without a service' do
      write_config(valid_config)
      _stdout, _stderr, status = run_config_manager('test')
      expect(status.exitstatus).to eq(1)
    end

    it 'shows the targets of a service' do
      write_config(valid_config)
      FileUtils.mkdir_p(File.join(@root, 'apps/demo'))
      stdout, stderr, status = run_config_manager('test', 'demo')
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to include('Service: demo', '  working_directory: "apps/demo"', '  excluded: false')
    end
  end
end
