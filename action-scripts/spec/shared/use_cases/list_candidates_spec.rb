require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::Shared::ListCandidates do
  let(:config) do
    Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [
      { 'id' => 'kustomize', 'path' => 'overlays/{environment}', 'exclude' => [{ 'environment' => 'production' }] },
      { 'id' => 'container', 'path' => '.' }
    ] }])
  end
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:directory_scanner) { Infrastructure::DirectoryScanner.new(repository_root: @root) }
  subject(:use_case) do
    described_class.new(
      config_client: config_client,
      resolve_environments: UseCases::Shared::ResolveEnvironments.new(directory_scanner: directory_scanner),
      enumerate_targets: UseCases::Shared::EnumerateTargets.new(directory_scanner: directory_scanner)
    )
  end

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  def directory(path)
    FileUtils.mkdir_p(File.join(@root, path))
  end

  def list(services: nil, environments: nil)
    result = use_case.execute(services: services, environments: environments)
    expect(result).to be_success
    result.value
  end

  it 'returns excluded candidates with the others' do
    %w[dystopia/demo/overlays/develop dystopia/demo/overlays/production].each { |path| directory(path) }
    expect(list(services: ['demo']).map { |candidate| [candidate.stack.id, candidate.environment, candidate.excluded?] }).to eq([
      ['kustomize', 'develop', false], ['kustomize', 'production', true], ['container', nil, false]
    ])
  end

  it 'lists every service when services is nil' do
    %w[dystopia/demo dystopia/api].each { |path| directory(path) }
    expect(list.map(&:service)).to eq(%w[api demo])
  end

  it 'limits candidates to the given services and environments' do
    %w[dystopia/demo/overlays/develop dystopia/demo/overlays/production dystopia/api/overlays/develop].each { |path| directory(path) }
    candidates = list(services: ['demo'], environments: ['develop'])
    expect(candidates.map { |candidate| [candidate.service, candidate.stack.id, candidate.environment] }).to eq([
      ['demo', 'kustomize', 'develop'], ['demo', 'container', nil]
    ])
  end

  it 'fails when an environment is outside the union' do
    directory('dystopia/demo/overlays/develop')
    result = use_case.execute(services: ['demo'], environments: ['qa'])
    expect(result).to be_failure
    expect(result.error_message).to eq('Target environments not found in configuration: qa')
  end
end
