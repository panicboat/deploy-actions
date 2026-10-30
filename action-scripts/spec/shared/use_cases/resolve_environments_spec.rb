require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::Shared::ResolveEnvironments do
  let(:scanner) { Infrastructure::DirectoryScanner.new(repository_root: @root) }
  let(:config) { build(:workflow_config) }
  subject(:use_case) { described_class.new(directory_scanner: scanner) }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  def directory(path)
    FileUtils.mkdir_p(File.join(@root, path))
  end

  def resolve(requested, with: config)
    use_case.execute(config: with, requested: requested)
  end

  [nil, []].each do |input|
    it "selects all declared environments for #{input.inspect}" do
      result = resolve(input)
      expect(result).to be_success
      expect(result.value).to eq(%w[develop production])
    end
  end

  it 'deduplicates requested environments preserving their order' do
    expect(resolve(%w[production production develop]).value).to eq(%w[production develop])
  end

  it 'rejects unknown environment names' do
    result = resolve(%w[preview develop staging])
    expect(result).to be_failure
    expect(result.error_message).to eq('Target environments not found in configuration: preview, staging')
    expect(result.value).to be_nil
  end

  it 'selects no environment for a common-only configuration' do
    common = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }])
    expect(resolve(nil, with: common).value).to eq([])
  end

  it 'accepts discovered environments and combines them with declared names' do
    directory('apps/demo/preview')
    discovered = Entities::WorkflowConfigParser.parse('services' => [
      { 'id' => 'plain', 'roots' => ['{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => 'aws', 'environments' => { 'production' => {} } }] },
      { 'id' => 'apps', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }
    ])
    expect(resolve(nil, with: discovered).value).to eq(%w[production preview])
    expect(resolve(['preview'], with: discovered).value).to eq(['preview'])
    expect(resolve(['unknown'], with: discovered)).to be_failure
  end

  it 'combines declared and discovered environments without applying exclusions' do
    %w[teams/platform/demo/production teams/platform/demo/.preview teams/sandbox/api/production teams/platform/.hidden/hidden].each { |path| directory(path) }
    combined = Entities::WorkflowConfigParser.parse('services' => [
      { 'id' => 'plain', 'roots' => ['{service}'], 'stacks' => [
        { 'id' => 'aws', 'path' => 'aws', 'environments' => { 'production' => {}, 'develop' => {} } },
        { 'id' => 'container', 'path' => '.' }
      ] },
      { 'id' => 'teams', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}', 'exclude' => [{ 'environment' => '.preview' }] }] }
    ])
    expect(resolve(nil, with: combined).value).to eq(%w[production develop .preview])
    directory('teams/platform/demo/sandbox')
    expect(resolve(nil, with: combined).value).to eq(%w[production develop .preview sandbox])
  end

  %w[.hidden a.b].each do |name|
    it "ignores environments found only under a directory named #{name}" do
      discovered = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'kustomize', 'path' => 'overlays/{environment}' }] }])
      directory("dystopia/#{name}/overlays/qa")
      expect(resolve(nil, with: discovered).value).not_to include('qa')
      expect(resolve(['qa'], with: discovered)).to be_failure
    end

    it "resolves environments next to an unreadable directory named #{name}" do
      discovered = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'kustomize', 'path' => 'overlays/{environment}' }] }])
      directory('dystopia/demo/overlays/develop')
      directory("dystopia/#{name}/overlays/qa")
      path = File.join(@root, 'dystopia', name)
      File.chmod(0, path)
      expect(resolve(nil, with: discovered).value).to eq(['develop'])
    ensure
      File.chmod(0o755, path) if path
    end
  end

  it 'returns no environments when inferred directories are absent' do
    absent = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }])
    expect(resolve(nil, with: absent).value).to eq([])
  end

  it 'propagates permission errors during environment discovery' do
    directory('blocked/demo/production')
    path = File.join(@root, 'blocked')
    File.chmod(0, path)
    blocked = Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['blocked/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => '{environment}' }] }])
    expect { resolve(nil, with: blocked) }.to raise_error(Errno::EACCES)
  ensure
    File.chmod(0o755, path) if path
  end
end
