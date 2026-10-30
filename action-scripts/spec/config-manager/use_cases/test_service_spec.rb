require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::ConfigManagement::TestService do
  let(:config_hash) { attributes_for(:workflow_config).fetch(:config_hash) }
  let(:config) { Entities::WorkflowConfigParser.parse(config_hash) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:directory_scanner) { Infrastructure::DirectoryScanner.new(repository_root: @root) }
  subject(:use_case) do
    described_class.new(
      list_candidates: UseCases::Shared::ListCandidates.new(
        config_client: config_client,
        resolve_environments: UseCases::Shared::ResolveEnvironments.new(directory_scanner: directory_scanner),
        enumerate_targets: UseCases::Shared::EnumerateTargets.new(directory_scanner: directory_scanner)
      )
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

  def use_service(roots:, stacks:)
    config_hash['services'] = [{ 'id' => 'app', 'roots' => roots, 'stacks' => stacks }]
  end

  def candidates(service: 'demo', environment: nil)
    result = use_case.execute(service_name: service, environment: environment)
    expect(result).to be_success
    result.value
  end

  it 'returns target candidates for every environment when the environment is omitted' do
    %w[dystopia/demo/aws/develop dystopia/demo/aws/production system-components/demo/aws/develop system-components/demo/aws/production].each { |path| directory(path) }
    rows = candidates
    expect(rows).to all(be_a(Entities::TargetCandidate))
    expect(rows.length).to eq(6)
    expect(rows.map(&:working_directory).uniq.length).to eq(6)
    expect(rows.count { |row| row.environment.nil? }).to eq(2)
    expect(rows.map(&:excluded?).uniq).to eq([false])
  end

  it 'returns excluded targets with excluded? true' do
    config_hash['services'].first['stacks'].first['exclude'] = [{ 'service' => 'demo', 'environment' => 'production' }]
    directory('dystopia/demo/aws/production')
    rows = candidates(environment: 'production')
    aws = rows.find { |row| row.stack.id == 'aws' }
    expect(aws.excluded?).to be(true)
    expect(aws.to_deployment_target.attributes).to eq('type' => 'terragrunt', 'aws_region' => 'us-west-2')
    expect(rows.find { |row| row.stack.id == 'container' }.excluded?).to be(false)
  end

  it 'retains distinct identities and captures at the same directory' do
    use_service(roots: ['teams/{team}/{service}'], stacks: [
      { 'id' => 'aws', 'path' => '.', 'attributes' => { 'token' => nil } },
      { 'id' => 'stripe', 'path' => '.', 'attributes' => { 'repository' => 'registry.example.com' } }
    ])
    directory('teams/platform/demo')
    rows = candidates
    expect(rows.map { |row| row.stack.id }).to eq(%w[aws stripe])
    expect(rows.map(&:captures)).to eq([{ 'team' => 'platform' }] * 2)
    expect(rows.first.to_deployment_target.attributes).to eq('token' => nil)
  end

  it 'returns dot-prefixed environment and custom placeholder values' do
    use_service(roots: ['teams/{team}/{service}'], stacks: [{ 'id' => 'terragrunt', 'path' => '{environment}', 'environments' => { '.preview' => {} }, 'exclude' => [{ 'team' => '.platform', 'environment' => '.preview' }] }])
    directory('teams/.platform/demo/.preview')
    rows = candidates(environment: '.preview')
    expect(rows.length).to eq(1)
    expect(rows.first.to_deployment_target.to_matrix_item).to include(team: '.platform', environment: '.preview')
    expect(rows.first.excluded?).to be(true)
  end

  it 'returns inferred environments and renders common attribute templates' do
    use_service(roots: ['teams/{team}/{service}'], stacks: [
      { 'id' => 'kubernetes', 'path' => '{environment}', 'exclude' => [{ 'environment' => 'production' }] },
      { 'id' => 'container', 'path' => '.', 'attributes' => { 'repository' => 'ghcr.io/{team}/{service}' } }
    ])
    %w[teams/payments/demo/production teams/payments/demo/preview].each { |path| directory(path) }
    rows = candidates(environment: 'production')
    expect(rows.length).to eq(2)
    expect(rows.find { |row| row.stack.id == 'kubernetes' }.excluded?).to be(true)
    expect(rows.find { |row| row.stack.id == 'container' }.to_deployment_target.attributes).to eq('repository' => 'ghcr.io/payments/demo')
    expect(candidates.map(&:environment)).to contain_exactly('production', 'preview', nil)
  end

  it 'returns an empty list when no directory matches' do
    expect(candidates(service: 'unregistered')).to eq([])
  end

  it 'deduplicates identical candidates' do
    use_service(roots: ['dystopia/{service}', 'dystopia/{service}'], stacks: [{ 'id' => 'container', 'path' => '.' }])
    directory('dystopia/demo')
    expect(candidates.length).to eq(1)
  end

  it 'fails for an unknown environment' do
    result = use_case.execute(service_name: 'demo', environment: 'qa')
    expect(result).to be_failure
    expect(result.error_message).to eq('Target environments not found in configuration: qa')
  end

  it 'fails for conflicting captures before applying exclusions' do
    use_service(roots: ['teams/{team}/{service}', 'teams/{product}/{service}'], stacks: [{ 'id' => 'container', 'path' => '.', 'exclude' => [{ 'team' => 'platform' }] }])
    directory('teams/platform/demo')
    result = use_case.execute(service_name: 'demo', environment: nil)
    expect(result).to be_failure
    expect(result.error_message).to include('Conflicting captures')
  end

  it 'fails with the enumeration error' do
    allow(directory_scanner).to receive(:resolve).and_raise(Errno::EACCES)
    result = use_case.execute(service_name: 'demo', environment: nil)
    expect(result).to be_failure
    expect(result.error_message).to eq('Failed to test service configuration: Permission denied')
  end

  it 'fails with the configuration error' do
    allow(config_client).to receive(:load_workflow_config).and_raise(ArgumentError, 'services[0].roots is empty')
    result = use_case.execute(service_name: 'demo', environment: nil)
    expect(result).to be_failure
    expect(result.error_message).to eq('Failed to test service configuration: services[0].roots is empty')
  end
end
