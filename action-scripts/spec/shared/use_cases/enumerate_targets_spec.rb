require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::Shared::EnumerateTargets do
  let(:scanner) { Infrastructure::DirectoryScanner.new(repository_root: @root) }
  let(:config) do
    Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [
      { 'id' => 'kustomize', 'path' => 'overlays/{environment}', 'exclude' => [{ 'environment' => 'production' }] },
      { 'id' => 'container', 'path' => '.' }
    ] }])
  end
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

  def enumerate(services: nil, environments: %w[develop production])
    result = use_case.execute(config: config, services: services, environments: environments)
    expect(result).to be_success
    result.value
  end

  it 'returns excluded candidates marked as excluded' do
    %w[dystopia/demo/overlays/develop dystopia/demo/overlays/production].each { |path| directory(path) }
    expect(enumerate.map { |candidate| [candidate.stack.id, candidate.environment, candidate.excluded?] }).to eq([
      ['kustomize', 'develop', false], ['kustomize', 'production', true], ['container', nil, false]
    ])
  end

  it 'limits candidates to the given services' do
    %w[dystopia/demo/overlays/develop dystopia/api/overlays/develop].each { |path| directory(path) }
    candidates = enumerate(services: ['demo'])
    expect(candidates).not_to be_empty
    expect(candidates.map(&:service).uniq).to eq(['demo'])
  end

  it 'enumerates every service when services are nil' do
    %w[dystopia/demo dystopia/api].each { |path| directory(path) }
    expect(enumerate.map(&:service)).to eq(%w[api demo])
  end

  it 'skips hidden services' do
    directory('dystopia/.hidden/overlays/develop')
    expect(enumerate).to eq([])
  end

  it 'enumerates targets next to an unreadable hidden service' do
    directory('dystopia/demo/overlays/develop')
    directory('dystopia/.cache/overlays/develop')
    path = File.join(@root, 'dystopia/.cache')
    File.chmod(0, path)
    expect(enumerate.map(&:working_directory)).to eq(['dystopia/demo/overlays/develop', 'dystopia/demo'])
  ensure
    File.chmod(0o755, path) if path
  end
end
