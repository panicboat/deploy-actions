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

  def use_service(roots:, stacks:)
    config_hash['services'] = [{ 'id' => 'app', 'roots' => roots, 'stacks' => stacks }]
  end

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
      let(:validation) { UseCases::ConfigManagement::Validation.new(config: build(:workflow_config), summary: 'Configuration is valid') }
      let(:validation_result) { Entities::Result.success(validation) }

      it 'presents successful validation result' do
        allow(validate_config_use_case).to receive(:execute).and_return(validation_result)
        allow(presenter).to receive(:present_config_validation_result)

        controller.validate_configuration

        expect(presenter).to have_received(:present_config_validation_result).with(
          valid: true,
          config: validation.config,
          summary: 'Configuration is valid'
        )
      end
    end

    context 'with invalid configuration' do
      let(:validation_result) { Entities::Result.failure('Missing required field: stacks') }

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
      %w[dystopia/demo/aws/develop dystopia/demo/aws/production system-components/demo/aws/develop system-components/demo/aws/production].each { |path| directory(path) }
      rows = matches
      expect(rows.length).to eq(6)
      expect(rows.map { |row| row[:target].working_directory }.uniq.length).to eq(6)
      expect(rows.count { |row| row[:target].environment.nil? }).to eq(2)
      expect(rows.map { |row| row[:excluded] }.uniq).to eq([false])
    end

    it 'retains environment attributes and includes excluded targets for diagnosis' do
      config_hash['services'].first['stacks'].first['exclude'] = [{ 'service' => 'demo', 'environment' => 'production' }]
      directory('dystopia/demo/aws/production')
      rows = matches(environment: 'production')
      aws = rows.find { |row| row[:target].stack == 'aws' }
      expect(aws[:excluded]).to be(true)
      expect(aws[:target].attributes).to eq('type' => 'terragrunt', 'aws_region' => 'us-west-2')
      expect(rows.find { |row| row[:target].stack == 'container' }[:excluded]).to be(false)
    end

    it 'retains distinct identities and captures at the same directory' do
      use_service(roots: ['teams/{team}/{service}'], stacks: [
        { 'id' => 'aws', 'path' => '.', 'attributes' => { 'token' => nil } },
        { 'id' => 'stripe', 'path' => '.', 'attributes' => { 'repository' => 'registry.example.com' } }
      ])
      directory('teams/platform/demo')
      rows = matches
      expect(rows.map { |row| row[:target].stack }).to eq(%w[aws stripe])
      expect(rows.map { |row| row[:target].captures }).to eq([{ 'team' => 'platform' }] * 2)
      expect(rows.first[:target].attributes).to eq('token' => nil)
    end

    it 'diagnoses dot-prefixed environment and custom placeholder values' do
      use_service(roots: ['teams/{team}/{service}'], stacks: [{ 'id' => 'terragrunt', 'path' => '{environment}', 'environments' => { '.preview' => {} }, 'exclude' => [{ 'team' => '.platform', 'environment' => '.preview' }] }])
      directory('teams/.platform/demo/.preview')
      rows = matches(environment: '.preview')
      expect(rows.length).to eq(1)
      expect(rows.first[:target].to_matrix_item).to include(team: '.platform', environment: '.preview')
      expect(rows.first[:excluded]).to be(true)
    end

    it 'diagnoses inferred environments and renders common attribute templates' do
      use_service(roots: ['teams/{team}/{service}'], stacks: [
        { 'id' => 'kubernetes', 'path' => '{environment}', 'exclude' => [{ 'environment' => 'production' }] },
        { 'id' => 'container', 'path' => '.', 'attributes' => { 'repository' => 'ghcr.io/{team}/{service}' } }
      ])
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
      use_service(roots: ['dystopia/{service}', 'dystopia/{service}'], stacks: [{ 'id' => 'container', 'path' => '.' }])
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
      use_service(roots: ['teams/{team}/{service}', 'teams/{product}/{service}'], stacks: [{ 'id' => 'container', 'path' => '.', 'exclude' => [{ 'team' => 'platform' }] }])
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

    it 'reports the configuration error when validation fails' do
      allow(validate_config_use_case).to receive(:execute).and_return(build(:result_failure, error_message: 'services[0].roots is empty'))

      controller.run_diagnostics

      expect(presenter).to have_received(:present_diagnostic_results) do |args|
        validation_check = args[:results].find { |r| r[:check] == 'Configuration Validation' }
        expect(validation_check).to include(status: 'FAIL', details: 'services[0].roots is empty')
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
    let(:template) { controller.send(:build_config_template) }
    let(:template_hash) { YAML.safe_load(template, aliases: true) }

    it 'presents the template it builds' do
      allow(presenter).to receive(:present_config_template)
      controller.generate_config_template
      expect(presenter).to have_received(:present_config_template).with(template: template)
    end

    it 'generates a template that passes validation' do
      expect { Entities::WorkflowConfig.new(template_hash) }.not_to raise_error
    end

    it 'defines profiles and one service with roots, ignore, and the dockerfile, kustomize, and aws stacks' do
      service = template_hash.fetch('services').first
      expect(template_hash.fetch('profiles').keys).to eq(%w[aws-develop aws-production])
      expect(service.slice('id', 'roots', 'ignore')).to eq('id' => 'app', 'roots' => ['dystopia/{service}', 'system-components/{service}'], 'ignore' => ['**/README.md'])
      expect(service.fetch('stacks').map { |stack| stack['id'] }).to eq(%w[dockerfile kustomize aws])
    end

    it 'names the tool in the type attribute of every stack' do
      stacks = template_hash.fetch('services').first.fetch('stacks')
      expect(stacks.to_h { |stack| [stack['id'], stack.dig('attributes', 'type')] }).to eq('dockerfile' => 'container', 'kustomize' => 'kustomize', 'aws' => 'terragrunt')
    end

    it 'discovers kustomize environments and declares aws environments from profiles' do
      kustomize, aws = template_hash.fetch('services').first.fetch('stacks').values_at(1, 2)
      expect(kustomize).not_to have_key('environments')
      expect(aws.fetch('environments')).to eq('develop' => { 'use' => ['aws-develop'] }, 'production' => { 'use' => ['aws-production'] })
    end

    it 'uses the placeholder registry' do
      dockerfile = template_hash.fetch('services').first.fetch('stacks').first
      expect(dockerfile.dig('attributes', 'repository')).to eq('registry.example.com/{service}')
    end

    it 'uses the placeholder account id' do
      expect(template).to include('arn:aws:iam::123456789012:role/')
      expect(template).not_to match(/arn:aws:iam::(?!123456789012:)/)
    end

    it 'accepts the repository sample with the same model' do
      config = Entities::WorkflowConfig.new(YAML.safe_load(File.read(File.expand_path('../../../workflow-config.yaml', __dir__))))
      expect(config.stacks.map { |stack| stack['id'] }).to include('aws', 'dockerfile', 'kustomize')
    end
  end
end
