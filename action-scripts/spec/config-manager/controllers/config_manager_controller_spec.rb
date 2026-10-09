# spec/config-manager/controllers/config_manager_controller_spec.rb

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Interfaces::Controllers::ConfigManagerController do
  let(:validate_config_use_case) { double('ValidateConfig') }
  let(:config_hash) { attributes_for(:workflow_config).fetch(:config_hash) }
  let(:config) { Entities::WorkflowConfig.new(config_hash) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:file_client) { Infrastructure::FileSystemClient.new }
  let(:presenter) { double('Presenter') }

  subject(:controller) do
    described_class.new(
      validate_config_use_case: validate_config_use_case,
      config_client: config_client,
      file_client: file_client,
      presenter: presenter
    )
  end

  describe '#validate_configuration' do
    context 'with valid configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: true,
          config: build(:workflow_config),
          validation_summary: 'Configuration is valid'
        )
      end

      it 'presents successful validation result' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: true,
          config: validation_result.config,
          summary: 'Configuration is valid'
        )
      end
    end

    context 'with invalid configuration' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: ['Missing required field: stacks'],
          error_message: 'Validation failed'
        )
      end

      it 'presents validation errors' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: false,
          errors: ['Missing required field: stacks']
        )
      end
    end

    context 'with validation error but no specific errors' do
      let(:validation_result) do
        double(
          'Result',
          success?: false,
          validation_errors: nil,
          error_message: 'General validation error'
        )
      end

      it 'uses error message as fallback' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: false,
          errors: ['General validation error']
        )
      end
    end
  end

  describe '#show_configuration' do
    context 'with successful config loading' do
      let(:config) { build(:workflow_config) }

      it 'presents configuration details' do
        allow(config_client).to receive(:load_workflow_config).and_return(config)
        allow(presenter).to receive(:present_config_details)

        controller.show_configuration

        expect(presenter).to have_received(:present_config_details).with(config: config)
      end
    end

    context 'with config loading error' do
      let(:error) { StandardError.new('Config file not found') }

      it 'presents error result' do
        allow(config_client).to receive(:load_workflow_config).and_raise(error)
        allow(presenter).to receive(:present_error)

        controller.show_configuration

        expect(presenter).to have_received(:present_error) do |result|
          expect(result.failure?).to be true
          expect(result.error_message).to include('Config file not found')
        end
      end
    end
  end

  describe '#test_service_configuration' do
    around do |example|
      original = ENV['SOURCE_REPO_PATH']
      Dir.mktmpdir do |root|
        @root = root
        FileUtils.mkdir_p(File.join(root, '.git'))
        ENV['SOURCE_REPO_PATH'] = root
        example.run
      end
    ensure
      ENV['SOURCE_REPO_PATH'] = original
    end

    def directory(path)
      FileUtils.mkdir_p(File.join(@root, path))
    end

    def matches(environment: nil, service: 'demo')
      allow(presenter).to receive(:present_service_test_result)
      controller.test_service_configuration(service_name: service, environment: environment)
      expect(presenter).to have_received(:present_service_test_result) { |args| return args.fetch(:matches) }
    end

    it 'diagnoses unregistered services across every shared product path and common stack' do
      %w[dystopia/demo/aws/develop dystopia/demo/aws/production system-components/demo/infrastructure/aws/develop system-components/demo/infrastructure/aws/production].each { |path| directory(path) }
      rows = matches
      expect(rows.length).to eq(6)
      expect(rows.map { |row| row[:target].working_directory }.uniq.length).to eq(6)
      expect(rows.count { |row| row[:target].environment.nil? }).to eq(2)
      expect(rows.map { |row| row[:excluded] }.uniq).to eq([false])
    end

    it 'retains environment attributes and includes excluded targets for diagnosis' do
      config_hash['stacks'].first['exclude'] = [{ 'service' => 'demo', 'environment' => 'production' }]
      directory('dystopia/demo/aws/production')
      rows = matches(environment: 'production')
      aws = rows.find { |row| row[:target].stack_id == 'aws' }
      expect(aws[:excluded]).to be(true)
      expect(aws[:target].attributes).to eq('aws_region' => 'us-west-2')
      expect(rows.find { |row| row[:target].stack_id == 'container' }[:excluded]).to be(false)
    end

    it 'retains distinct identities and captures at the same directory' do
      config_hash['stacks'] = [
        { 'name' => 'terragrunt', 'id' => 'aws', 'paths' => ['teams/{team}/{service}'], 'attributes' => { 'token' => nil } },
        { 'name' => 'terragrunt', 'id' => 'stripe', 'paths' => ['teams/{team}/{service}'], 'attributes' => { 'repository' => 'registry.example.com' } }
      ]
      directory('teams/platform/demo')
      rows = matches
      expect(rows.map { |row| row[:target].stack_id }).to eq(%w[aws stripe])
      expect(rows.map { |row| row[:target].captures }).to eq([{ 'team' => 'platform' }] * 2)
      expect(rows.first[:target].attributes).to eq('token' => nil)
    end

    it 'diagnoses dot-prefixed environment and custom placeholder values' do
      config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => ['teams/{team}/{service}/{environment}'], 'environments' => { '.preview' => {} }, 'exclude' => [{ 'team' => '.platform', 'environment' => '.preview' }] }]
      directory('teams/.platform/demo/.preview')
      rows = matches(environment: '.preview')
      expect(rows.length).to eq(1)
      expect(rows.first[:target].to_matrix_item).to include(team: '.platform', environment: '.preview')
      expect(rows.first[:excluded]).to be(true)
    end

    it 'diagnoses inferred environments and renders common attribute templates' do
      config_hash['stacks'] = [
        { 'name' => 'kubernetes', 'paths' => ['teams/{team}/{service}/{environment}'], 'exclude' => [{ 'environment' => 'production' }] },
        { 'name' => 'container', 'paths' => ['teams/{team}/{service}'], 'attributes' => { 'repository' => 'ghcr.io/{team}/{service}' } }
      ]
      %w[teams/payments/demo/production teams/payments/demo/preview].each { |path| directory(path) }
      rows = matches(environment: 'production')
      expect(rows.length).to eq(2)
      expect(rows.find { |row| row[:target].stack == 'kubernetes' }).to include(excluded: true)
      expect(rows.find { |row| row[:target].stack == 'container' }[:target].attributes).to eq('repository' => 'ghcr.io/payments/demo')
      expect(presenter).to receive(:present_service_test_result) do |args|
        expect(args[:matches].map { |row| row[:target].environment }).to contain_exactly('production', 'preview', nil)
      end
      controller.test_service_configuration(service_name: 'demo')
    end

    it 'returns an empty list when no directory matches' do
      expect(matches(service: 'unregistered')).to eq([])
    end

    it 'deduplicates identical matches' do
      config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['dystopia/{service}', 'dystopia/{service}'], 'attributes' => {} }]
      directory('dystopia/demo')
      expect(matches.length).to eq(1)
    end

    it 'reports unknown environments without presenting partial matches' do
      allow(presenter).to receive(:present_error)
      expect(presenter).not_to receive(:present_service_test_result)
      controller.test_service_configuration(service_name: 'demo', environment: 'preview')
      expect(presenter).to have_received(:present_error) { |result| expect(result.error_message).to include('preview') }
    end

    it 'reports conflicting captures before exclusions' do
      config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['teams/{team}/{service}', 'teams/{product}/{service}'], 'attributes' => {}, 'exclude' => [{ 'team' => 'platform' }] }]
      directory('teams/platform/demo')
      allow(presenter).to receive(:present_error)
      expect(presenter).not_to receive(:present_service_test_result)
      controller.test_service_configuration(service_name: 'demo')
      expect(presenter).to have_received(:present_error) { |result| expect(result.error_message).to include('Conflicting captures') }
    end

    it 'reports enumeration errors without presenting partial matches' do
      allow(file_client).to receive(:resolve_directories).and_raise(Errno::EACCES)
      allow(presenter).to receive(:present_error)
      expect(presenter).not_to receive(:present_service_test_result)
      controller.test_service_configuration(service_name: 'demo')
      expect(presenter).to have_received(:present_error) { |result| expect(result.error_message).to include('Permission denied') }
    end
  end

  describe '#run_diagnostics' do
    let(:config) { build(:workflow_config) }

    before do
      allow(validate_config_use_case).to receive(:execute).and_return(build(:result_success))
      allow(presenter).to receive(:present_diagnostic_results)
      allow(File).to receive(:exist?).and_return(true)
      
      # Mock git status
      status_mock = double('Process::Status', success?: true)
      allow(controller).to receive(:`).with('git status --porcelain 2>/dev/null') do
        $? = status_mock
        ''
      end
      
      # Mock environment variables
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return('test_token')
      allow(ENV).to receive(:[]).with('GITHUB_REPOSITORY').and_return('test/repo')
    end

    it 'runs comprehensive diagnostic checks' do
      controller.run_diagnostics

      expect(presenter).to have_received(:present_diagnostic_results) do |args|
        results = args[:results]
        expect(results).to be_an(Array)
        expect(results.length).to eq(4)
        
        # Check that all diagnostic checks are included
        check_names = results.map { |r| r[:check] }
        expect(check_names).to include(
          'Configuration Validation',
          'Environment Variables',
          'Git Repository',
          'Configuration File'
        )
      end
    end

    context 'with missing environment variables' do
      before do
        allow(ENV).to receive(:[]).with('GITHUB_TOKEN').and_return(nil)
      end

      it 'reports missing environment variables' do
        controller.run_diagnostics

        expect(presenter).to have_received(:present_diagnostic_results) do |args|
          env_check = args[:results].find { |r| r[:check] == 'Environment Variables' }
          expect(env_check[:status]).to eq('FAIL')
          expect(env_check[:details]).to include('GITHUB_TOKEN')
        end
      end
    end
  end

  describe '#generate_config_template' do
    it 'generates a template accepted by the configuration model' do
      allow(presenter).to receive(:present_config_template)
      controller.generate_config_template
      expect(presenter).to have_received(:present_config_template) do |args|
        config = Entities::WorkflowConfig.new(YAML.safe_load(args.fetch(:template)))
        expect(config.stacks.map { |stack| stack['id'] }).to include('aws', 'container')
        expect(config.environment_names).to include('develop', 'production')
      end
    end

    it 'accepts the repository sample with the same model' do
      config = Entities::WorkflowConfig.new(YAML.safe_load(File.read(File.expand_path('../../../workflow-config.yaml', __dir__))))
      expect(config.stacks.map { |stack| stack['id'] }).to include('aws', 'container')
    end
  end
end
