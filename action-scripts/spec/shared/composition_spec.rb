require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Composition do
  around do |example|
    keys = %w[SOURCE_REPO_PATH WORKFLOW_CONFIG_PATH GITHUB_TOKEN GITHUB_REPOSITORY GITHUB_ACTIONS GITHUB_OUTPUT]
    original = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  let(:config_yaml) { { 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }] }.to_yaml }

  it 'reads workflow-config.yaml from the working directory when WORKFLOW_CONFIG_PATH is unset' do
    File.write(File.join(@root, 'workflow-config.yaml'), config_yaml)
    Dir.chdir(@root) do
      expect(described_class.config_client.load_workflow_config.stacks.first.id).to eq('container')
    end
  end

  it 'reads the configuration from WORKFLOW_CONFIG_PATH when set' do
    path = File.join(@root, 'custom.yaml')
    File.write(path, config_yaml)
    ENV['WORKFLOW_CONFIG_PATH'] = path
    expect(described_class.config_client.load_workflow_config.stacks.first.id).to eq('container')
  end

  it 'locates the repository root from SOURCE_REPO_PATH' do
    FileUtils.mkdir_p(File.join(@root, '.git'))
    ENV['SOURCE_REPO_PATH'] = @root
    expect(described_class.repository_root).to eq(@root)
  end

  it 'builds the git client and directory scanner on the repository root' do
    FileUtils.mkdir_p(File.join(@root, '.git'))
    FileUtils.mkdir_p(File.join(@root, 'apps/demo'))
    ENV['SOURCE_REPO_PATH'] = @root
    expect(described_class.git_client).to be_a(Infrastructure::GitClient)
    expect(described_class.directory_scanner.resolve(pattern: 'apps/{service}')).to eq([{ working_directory: 'apps/demo', captures: { 'service' => 'demo' } }])
  end

  it 'raises when the GitHub token is missing' do
    ENV['GITHUB_REPOSITORY'] = 'owner/repo'
    expect { described_class.github_client }.to raise_error(RuntimeError, 'GITHUB_TOKEN and GITHUB_REPOSITORY are required')
  end

  it 'raises when the GitHub repository is missing' do
    ENV['GITHUB_TOKEN'] = 'token'
    expect { described_class.github_client }.to raise_error(RuntimeError, 'GITHUB_TOKEN and GITHUB_REPOSITORY are required')
  end

  it 'builds the GitHub client when the token and repository are present' do
    ENV['GITHUB_TOKEN'] = 'token'
    ENV['GITHUB_REPOSITORY'] = 'owner/repo'
    expect(described_class.github_client).to be_a(Infrastructure::GitHubClient)
  end

  it 'reports whether it runs in GitHub Actions' do
    expect(described_class.github_actions?).to be(false)
    ENV['GITHUB_ACTIONS'] = 'true'
    expect(described_class.github_actions?).to be(true)
  end

  it 'returns the GitHub output path' do
    expect(described_class.github_output_path).to be_nil
    ENV['GITHUB_OUTPUT'] = File.join(@root, 'output')
    expect(described_class.github_output_path).to eq(File.join(@root, 'output'))
  end

  it 'builds the console presenter outside GitHub Actions' do
    expect(described_class.presenter).to be_a(Interfaces::Presenters::ConsolePresenter)
  end

  it 'builds the GitHub Actions presenter on GITHUB_OUTPUT in GitHub Actions' do
    output_path = File.join(@root, 'output')
    File.write(output_path, '')
    ENV['GITHUB_ACTIONS'] = 'true'
    ENV['GITHUB_OUTPUT'] = output_path
    presenter = described_class.presenter
    expect(presenter).to be_a(Interfaces::Presenters::GitHubActionsPresenter)
    expect { presenter.present_deployment_matrix(deployment_targets: [], deploy_labels: [], target_environments: [], pr_number: 1) }.to output.to_stdout
    expect(File.read(output_path)).to include('has-targets=false')
  end

  it 'raises in GitHub Actions when GITHUB_OUTPUT is not set' do
    ENV['GITHUB_ACTIONS'] = 'true'
    expect { described_class.presenter }.to raise_error(RuntimeError, 'GITHUB_OUTPUT is not set')
  end

  it 'defines no presenter builder in any CLI container' do
    [ConfigManagerContainer, LabelDispatcherContainer, LabelResolverContainer].each do |container|
      expect(container).not_to respond_to(:build_presenter)
    end
  end
end
