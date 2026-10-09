require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::LabelResolver::GenerateMatrix do
  let(:config_hash) { attributes_for(:workflow_config).fetch(:config_hash) }
  let(:config) { Entities::WorkflowConfig.new(config_hash) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:file_client) { Infrastructure::FileSystemClient.new }
  subject(:use_case) { described_class.new(config_client: config_client, file_client: file_client) }

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

  def generate(labels: ['deploy:demo'], environments: [])
    use_case.execute(deploy_labels: labels.map { |label| Entities::DeployLabel.new(label) }, target_environments: environments)
  end

  def items(**options)
    result = generate(**options)
    expect(result).to be_success
    result.deployment_targets.map(&:to_matrix_item)
  end

  it 'generates every shared product path with attributes from its own environment' do
    %w[dystopia/demo/aws/develop dystopia/demo/aws/production system-components/demo/infrastructure/aws/develop system-components/demo/infrastructure/aws/production].each { |path| directory(path) }
    rows = items
    expect(rows.length).to eq(6)
    aws = rows.select { |row| row[:stack_id] == 'aws' }
    expect(aws.length).to eq(4)
    expect(aws.map { |row| [row[:environment], row[:aws_region]] }.uniq).to contain_exactly(['develop', 'ap-northeast-1'], ['production', 'us-west-2'])
    expect(rows.select { |row| row[:stack] == 'container' }).to all(include(environment: nil, repository: 'registry.example.com/app'))
    expect(rows).to all(satisfy { |row| !row.key?(:stack_convention_root) })
  end

  it 'keeps independent identities and attributes distinct' do
    config_hash['stacks'] = [
      { 'name' => 'terragrunt', 'id' => 'dystopia-aws', 'paths' => ['dystopia/{service}/aws/{environment}'], 'environments' => { 'develop' => { 'region' => 'a' } } },
      { 'name' => 'terragrunt', 'id' => 'components-aws', 'paths' => ['system-components/{service}/infrastructure/aws/{environment}'], 'environments' => { 'develop' => { 'region' => 'b' } } }
    ]
    directory('dystopia/demo/aws/develop'); directory('system-components/demo/infrastructure/aws/develop')
    expect(items.map { |row| [row[:stack_id], row[:region]] }).to contain_exactly(['dystopia-aws', 'a'], ['components-aws', 'b'])
  end

  it 'limits each stack to its declared environments' do
    config_hash['stacks'] = [
      { 'name' => 'terragrunt', 'paths' => ['dystopia/{service}/aws/{environment}'], 'environments' => { 'develop' => {} } },
      { 'name' => 'kubernetes', 'paths' => ['dystopia/{service}/k8s/{environment}'], 'environments' => { 'production' => {} } }
    ]
    %w[aws/develop aws/production k8s/develop k8s/production].each { |suffix| directory("dystopia/demo/#{suffix}") }
    expect(items.map { |row| [row[:stack], row[:environment]] }).to contain_exactly(['terragrunt', 'develop'], ['kubernetes', 'production'])
  end

  it 'discovers environments independently from every configured path' do
    config_hash['stacks'] = [
      { 'name' => 'kubernetes', 'paths' => ['teams/{team}/{service}/k8s/{environment}', 'components/{service}/overlays/{environment}'], 'exclude' => [{ 'team' => 'sandbox' }] }
    ]
    %w[teams/payments/demo/k8s/production teams/payments/demo/k8s/preview teams/sandbox/demo/k8s/production components/demo/overlays/staging teams/payments/.hidden/k8s/secret].each { |path| directory(path) }
    expect(items.map { |row| [row[:environment], row[:working_directory]] }).to contain_exactly(
      ['production', 'teams/payments/demo/k8s/production'], ['preview', 'teams/payments/demo/k8s/preview'], ['staging', 'components/demo/overlays/staging']
    )
    expect(items(environments: ['preview'])).to eq([
      { service: 'demo', environment: 'preview', stack: 'kubernetes', stack_id: 'kubernetes', working_directory: 'teams/payments/demo/k8s/preview', team: 'payments' }
    ])
  end

  it 'combines declared and discovered environments without inheriting stack exclusions' do
    config_hash['stacks'] = [
      { 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => { 'repository' => 'ghcr.io/{service}' } },
      { 'name' => 'terragrunt', 'id' => 'aws', 'paths' => ['dystopia/{service}/aws/{environment}'], 'environments' => { 'production' => {} }, 'exclude' => [{ 'environment' => 'production' }] },
      { 'name' => 'kubernetes', 'paths' => ['dystopia/{service}/overlays/{environment}'] }
    ]
    %w[dystopia/demo/aws/production dystopia/demo/overlays/production dystopia/api/overlays/preview].each { |path| directory(path) }
    rows = items(labels: ['deploy:all'])
    expect(rows.map { |row| [row[:service], row[:stack], row[:environment]] }).to contain_exactly(
      ['demo', 'container', nil], ['api', 'container', nil], ['demo', 'kubernetes', 'production'], ['api', 'kubernetes', 'preview']
    )
    expect(rows.select { |row| row[:stack] == 'container' }.map { |row| row[:repository] }).to contain_exactly('ghcr.io/demo', 'ghcr.io/api')
  end

  it 'expands environment attributes from the selected directory captures' do
    config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => ['teams/{team}/{service}/{environment}'], 'environments' => { 'production' => { 'role' => 'arn:aws:iam::123456789012:role/{team}-{service}-{environment}' } } }]
    directory('teams/payments/demo/production')
    expect(items.first).to include(role: 'arn:aws:iam::123456789012:role/payments-demo-production')
  end

  it 'expands common repository attributes from arbitrary path captures' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['teams/{team}/{service}'], 'attributes' => { 'repository' => 'ghcr.io/{team}/{service}' } }]
    directory('teams/payments/demo')
    expect(items).to eq([
      { service: 'demo', environment: nil, stack: 'container', stack_id: 'container', working_directory: 'teams/payments/demo', repository: 'ghcr.io/payments/demo', team: 'payments' }
    ])
  end

  it 'expands environment attributes when the path has no environment placeholder' do
    config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => ['teams/{team}/{service}'], 'environments' => {
      'production' => { 'role' => '{team}-{service}-{environment}' }, 'preview' => { 'role' => '{team}-{service}-{environment}' }
    } }]
    directory('teams/payments/demo')
    expect(items.map { |row| [row[:environment], row[:role]] }).to contain_exactly(['production', 'payments-demo-production'], ['preview', 'payments-demo-preview'])
  end

  it 'returns empty targets when inferred directories are absent' do
    config_hash['stacks'] = [{ 'name' => 'kubernetes', 'paths' => ['dystopia/{service}/overlays/{environment}'] }]
    expect(generate.data).to eq(deployment_targets: [], has_deployments: false, total_targets: 0)
  end

  it 'reuses an environment-less directory across its declared environments' do
    config_hash['stacks'].first['paths'] = ['dystopia/{service}/aws']
    directory('dystopia/demo/aws')
    rows = items.select { |row| row[:stack_id] == 'aws' }
    expect(rows.map { |row| [row[:working_directory], row[:environment], row[:aws_region]] }).to contain_exactly(['dystopia/demo/aws', 'develop', 'ap-northeast-1'], ['dystopia/demo/aws', 'production', 'us-west-2'])
  end

  it 'generates common targets once in a common-only configuration' do
    config_hash['stacks'] = [config_hash['stacks'].last]
    directory('dystopia/demo')
    expect(items(environments: nil)).to eq([{ service: 'demo', environment: nil, stack: 'container', stack_id: 'container', working_directory: 'dystopia/demo', repository: 'registry.example.com/app' }])
  end

  it 'discovers unregistered services for all labels and deduplicates overlapping labels' do
    directory('dystopia/demo/aws/develop'); directory('dystopia/api/aws/develop'); directory('dystopia/.hidden/aws/develop')
    rows = items(labels: ['deploy:all', 'deploy:demo', 'deploy:all'])
    expect(rows.length).to eq(4)
    expect(rows.map { |row| row[:service] }.uniq).to contain_exactly('demo', 'api')
  end

  it 'resolves every arbitrary placeholder value and exposes captures' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['teams/{team}/{service}'], 'attributes' => {} }]
    directory('teams/platform/demo'); directory('teams/sandbox/demo')
    expect(items.map { |row| [row[:team], row[:working_directory]] }).to contain_exactly(['platform', 'teams/platform/demo'], ['sandbox', 'teams/sandbox/demo'])
  end

  it 'applies service-only exclusions' do
    config_hash['stacks'].each { |stack| stack['exclude'] = [{ 'service' => 'demo' }] }
    directory('dystopia/demo/aws/develop')
    expect(items).to eq([])
  end

  it 'applies environment-only exclusions to environment-less paths' do
    config_hash['stacks'] = [config_hash['stacks'].first]
    config_hash['stacks'].first.merge!('paths' => ['dystopia/{service}/aws'], 'exclude' => [{ 'environment' => 'production' }])
    directory('dystopia/demo/aws')
    expect(items.map { |row| row[:environment] }).to eq(['develop'])
  end

  it 'applies arbitrary conditions with AND within a rule and OR across rules' do
    config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => ['teams/{team}/{service}/{environment}'], 'environments' => { 'develop' => {}, 'production' => {} }, 'exclude' => [{ 'team' => 'sandbox' }, { 'team' => 'platform', 'environment' => 'production' }] }]
    %w[platform sandbox].each { |team| %w[develop production].each { |env| directory("teams/#{team}/demo/#{env}") } }
    expect(items.map { |row| [row[:team], row[:environment]] }).to eq([['platform', 'develop']])
  end

  it 'does not match missing captures' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['teams/{team}/{service}', 'dystopia/{service}'], 'attributes' => {}, 'exclude' => [{ 'team' => 'sandbox' }] }]
    directory('teams/sandbox/demo'); directory('dystopia/demo')
    expect(items.map { |row| row[:working_directory] }).to eq(['dystopia/demo'])
  end

  it 'applies null environment exclusions to common targets' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => {}, 'exclude' => [{ 'environment' => nil }] }]
    directory('dystopia/demo')
    expect(items).to eq([])
  end

  it 'deduplicates identical paths and repeated labels' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['dystopia/{service}', 'dystopia/{service}'], 'attributes' => {} }]
    directory('dystopia/demo')
    expect(items(labels: ['deploy:demo', 'deploy:demo']).length).to eq(1)
  end

  [false, true].each do |reverse|
    it "rejects conflicting captures before exclusions with reversed paths #{reverse}" do
      paths = ['teams/{team}/{service}/aws', 'teams/{product}/{service}/aws']
      paths.reverse! if reverse
      config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => paths, 'attributes' => {}, 'exclude' => [{ 'team' => 'platform' }] }]
      directory('teams/platform/demo/aws')
      result = generate
      expect(result).to be_failure
      expect(result.error_message).to include('Conflicting captures', 'teams/platform/demo/aws')
      expect(result.data).not_to have_key(:deployment_targets)
    end
  end

  it 'returns failures without partial targets for enumeration errors' do
    directory('dystopia/demo/aws/develop')
    allow(file_client).to receive(:resolve_directories).and_call_original
    allow(file_client).to receive(:resolve_directories).with(pattern: 'system-components/{service}/infrastructure/aws/{environment}', values: { 'service' => 'demo', 'environment' => 'develop' }).and_raise(Errno::EACCES)
    result = generate
    expect(result).to be_failure
    expect(result.error_message).to include('Permission denied')
    expect(result.data).not_to have_key(:deployment_targets)
  end

  it 'returns failures for unknown environments even when no directory exists' do
    result = generate(environments: ['preview'])
    expect(result).to be_failure
    expect(result.error_message).to include('preview')
    expect(result.data).not_to have_key(:deployment_targets)
  end

  it 'deduplicates requested environments' do
    directory('dystopia/demo/aws/production')
    expect(items(environments: %w[production production]).count { |row| row[:stack_id] == 'aws' }).to eq(1)
  end

  it 'returns successful empty targets when directories are absent' do
    result = generate
    expect(result.data).to eq(deployment_targets: [], has_deployments: false, total_targets: 0)
  end

  it 'returns no targets for empty or invalid labels' do
    directory('dystopia/demo/aws/develop')
    expect(items(labels: [])).to eq([])
    expect(items(labels: ['other', 'deploy:demo:invalid'])).to eq([])
  end
  it 'returns a failure without partial targets for actual directory permission errors' do
    config_hash['stacks'] = [{ 'name' => 'container', 'paths' => ['readable/{service}', 'blocked/{service}'], 'attributes' => {} }]
    directory('readable/demo'); directory('blocked/demo')
    path = File.join(@root, 'blocked')
    File.chmod(0, path)
    expect { Dir.children(path) }.to raise_error(Errno::EACCES)
    result = generate
    expect(result).to be_failure
    expect(result.error_message).to include('Permission denied')
    expect(result.data).not_to have_key(:deployment_targets)
  ensure
    File.chmod(0o755, path) if path
  end

  it 'agrees with change detection for dot-prefixed environments and custom captures' do
    config_hash['stacks'] = [{ 'name' => 'terragrunt', 'paths' => ['teams/{team}/{service}/{environment}'], 'environments' => { '.preview' => { 'token' => nil } } }]
    directory('teams/.platform/demo/.preview')
    allow(file_client).to receive(:get_changed_files).and_return(['teams/.platform/demo/.preview/main.tf'])
    detector = UseCases::LabelManagement::DetectChangedServices.new(config_client: config_client, file_client: file_client)
    detection = detector.execute
    expect(detection.services_detected).to eq(['demo'])
    expect(items(labels: detection.deploy_labels.map(&:to_s))).to eq([
      { service: 'demo', stack: 'terragrunt', stack_id: 'terragrunt', environment: '.preview', working_directory: 'teams/.platform/demo/.preview', team: '.platform', token: nil }
    ])
  end

end
