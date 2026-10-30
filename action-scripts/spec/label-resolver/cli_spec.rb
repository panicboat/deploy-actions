require 'spec_helper'
require 'thor'
require 'open3'
require 'tmpdir'

RSpec.describe 'LabelResolverCLI' do
  let(:resolver_path) { File.expand_path('../../label-resolver/bin/resolver', __dir__) }

  before(:all) { load File.expand_path('../../label-resolver/bin/resolver', __dir__) }

  it 'does not start commands when loaded as a library' do
    expect(LabelResolverCLI).not_to receive(:start)
    load resolver_path
  end

  it 'registers only the resolve command' do
    expect(LabelResolverCLI.all_commands.keys - Thor.all_commands.keys).to contain_exactly('resolve')
  end

  [nil, '', '  '].each do |value|
    it "parses #{value.inspect} as all configured environments" do
      expect(LabelResolverCLI.new.send(:parse_environments, value)).to eq([])
    end
  end

  it 'parses comma-separated environment names' do
    expect(LabelResolverCLI.new.send(:parse_environments, ' develop,production ')).to eq(%w[develop production])
  end

  context 'with the resolve command' do
    let(:controller) { instance_double(Interfaces::Controllers::LabelResolverController) }

    before { allow(LabelResolverContainer).to receive(:resolve).with(:label_resolver_controller).and_return(controller) }

    it 'passes the PR number and the selected environments to the controller' do
      expect(controller).to receive(:resolve).with(pr_number: 123, environments: %w[develop staging]).and_return(Entities::Result.success)
      LabelResolverCLI.new.resolve('123', 'develop,staging')
    end

    it 'passes omitted environments as an empty selection' do
      expect(controller).to receive(:resolve).with(pr_number: 123, environments: []).and_return(Entities::Result.success)
      LabelResolverCLI.new.resolve('123')
    end

    it 'exits 1 when the controller returns a failure Result' do
      allow(controller).to receive(:resolve).and_return(Entities::Result.failure('boom'))
      expect { LabelResolverCLI.new.resolve('123') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it 'does not exit when the controller returns a success Result' do
      allow(controller).to receive(:resolve).and_return(Entities::Result.success)
      expect { LabelResolverCLI.new.resolve('123') }.not_to raise_error
    end
  end

  context 'when run as a process' do
    around do |example|
      Dir.mktmpdir do |root|
        @root = root
        Open3.capture3('git', 'init', '--quiet', root)
        File.write(File.join(root, 'workflow-config.yaml'), { 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }] }.to_yaml)
        example.run
      end
    end

    def run_resolver(*args, env: {})
      base_env = %w[GITHUB_ACTIONS GITHUB_OUTPUT GITHUB_TOKEN GITHUB_REPOSITORY SOURCE_REPO_PATH WORKFLOW_CONFIG_PATH].to_h { |key| [key, nil] }
      Open3.capture3(base_env.merge(env), RbConfig.ruby, resolver_path, *args, chdir: @root)
    end

    it 'exits 1 when resolve is called without a pull request number' do
      _stdout, _stderr, status = run_resolver('resolve')
      expect(status.exitstatus).to eq(1)
    end

    it 'exits 1 when resolve has no GitHub credentials' do
      _stdout, stderr, status = run_resolver('resolve', '12')
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('GITHUB_TOKEN and GITHUB_REPOSITORY are required')
    end

    it 'stops in GitHub Actions before reading labels when GITHUB_OUTPUT is not set' do
      stdout, stderr, status = run_resolver('resolve', '12', env: { 'GITHUB_ACTIONS' => 'true', 'GITHUB_TOKEN' => 'token', 'GITHUB_REPOSITORY' => 'owner/repo' })
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('GITHUB_OUTPUT is not set')
      expect(stdout).not_to include('Failed to retrieve PR labels')
    end
  end
end
