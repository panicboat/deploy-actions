require 'spec_helper'
require 'thor'
require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'LabelDispatcherCLI' do
  let(:dispatcher_path) { File.expand_path('../../label-dispatcher/bin/dispatcher', __dir__) }

  before(:all) { load File.expand_path('../../label-dispatcher/bin/dispatcher', __dir__) }

  it 'does not start commands when loaded as a library' do
    expect(LabelDispatcherCLI).not_to receive(:start)
    load dispatcher_path
  end

  it 'registers only the dispatch and test commands' do
    expect(LabelDispatcherCLI.all_commands.keys - Thor.all_commands.keys).to contain_exactly('dispatch', 'test')
  end

  {
    dispatch: [:dispatch, ['123'], { pr_number: 123 }],
    test: [:test, [], { base_ref: nil, head_ref: nil }]
  }.each do |command, (action, args, arguments)|
    context "with the #{command} command" do
      let(:controller) { instance_double(Interfaces::Controllers::LabelDispatcherController) }

      before { allow(LabelDispatcherContainer).to receive(:resolve).with(:label_dispatcher_controller).and_return(controller) }

      around do |example|
        original = $stdout
        $stdout = StringIO.new
        example.run
      ensure
        $stdout = original
      end

      it 'exits 1 when the controller returns a failure Result' do
        allow(controller).to receive(action).with(**arguments).and_return(Entities::Result.failure('boom'))
        expect { LabelDispatcherCLI.new.public_send(command, *args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it 'does not exit when the controller returns a success Result' do
        allow(controller).to receive(action).with(**arguments).and_return(Entities::Result.success)
        expect { LabelDispatcherCLI.new.public_send(command, *args) }.not_to raise_error
      end
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

    def run_dispatcher(*args, env: {})
      base_env = %w[GITHUB_ACTIONS GITHUB_OUTPUT GITHUB_TOKEN GITHUB_REPOSITORY SOURCE_REPO_PATH WORKFLOW_CONFIG_PATH].to_h { |key| [key, nil] }
      Open3.capture3(base_env.merge(env), RbConfig.ruby, dispatcher_path, *args, chdir: @root)
    end

    it 'runs test without GitHub credentials' do
      stdout, stderr, status = run_dispatcher('test')
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to include('Label Dispatch Results')
    end

    it 'labels a valid service and not a directory whose name is not a service' do
      git = ->(*args) { Open3.capture3('git', '-C', @root, '-c', 'user.name=t', '-c', 'user.email=t@example.com', *args) }
      %w[apps/a.b apps/api apps/all].each { |path| FileUtils.mkdir_p(File.join(@root, path)) }
      %w[apps/a.b/main.rb apps/api/main.rb apps/all/main.rb].each { |path| File.write(File.join(@root, path), "1\n") }
      git.call('add', '-A')
      git.call('commit', '-q', '-m', 'base')
      %w[apps/a.b/main.rb apps/api/main.rb].each { |path| File.write(File.join(@root, path), "2\n") }
      git.call('add', '-A')
      git.call('commit', '-q', '-m', 'change')

      stdout, stderr, status = run_dispatcher('test', '--base-ref=HEAD~1', '--head-ref=HEAD')

      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to include('Deploy Labels: deploy:api').and(include('apps/a.b/main.rb'))
      expect(stdout).not_to include('deploy:a.b')
    end

    it 'writes no step outputs in GitHub Actions' do
      output_path = File.join(@root, 'github-output')
      _stdout, stderr, status = run_dispatcher('test', env: { 'GITHUB_ACTIONS' => 'true', 'GITHUB_OUTPUT' => output_path })
      expect(status.exitstatus).to eq(0), stderr
      expect(File.exist?(output_path)).to be(false)
    end

    it 'exits 1 when test cannot diff the base ref' do
      stdout, _stderr, status = run_dispatcher('test', '--base-ref', 'missing-ref')
      expect(status.exitstatus).to eq(1)
      expect(stdout).to include('git diff failed')
    end

    it 'exits 1 when test is given a head ref without a base ref' do
      stdout, _stderr, status = run_dispatcher('test', '--head-ref', 'HEAD')
      expect(status.exitstatus).to eq(1)
      expect(stdout).to include('head_ref requires base_ref')
    end

    it 'exits 1 when dispatch is called without a pull request number' do
      _stdout, _stderr, status = run_dispatcher('dispatch')
      expect(status.exitstatus).to eq(1)
    end

    it 'exits 1 when dispatch has no GitHub credentials' do
      _stdout, stderr, status = run_dispatcher('dispatch', '12')
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('GITHUB_TOKEN and GITHUB_REPOSITORY are required')
    end

    it 'stops in GitHub Actions before dispatching when GITHUB_OUTPUT is not set' do
      _stdout, stderr, status = run_dispatcher('dispatch', '12', env: { 'GITHUB_ACTIONS' => 'true', 'GITHUB_TOKEN' => 'token', 'GITHUB_REPOSITORY' => 'owner/repo' })
      expect(status.exitstatus).to eq(1)
      expect(stderr).to include('GITHUB_OUTPUT is not set')
      expect(stderr).not_to include('Failed to get PR info')
    end
  end
end
