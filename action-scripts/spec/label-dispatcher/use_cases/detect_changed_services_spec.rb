require 'spec_helper'

RSpec.describe UseCases::LabelManagement::DetectChangedServices do
  let(:stack) { { 'id' => 'terragrunt', 'path' => 'aws/{environment}', 'environments' => { 'develop' => {}, 'production' => {} }, 'exclude' => [{ 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' }] } }
  let(:service) { { 'id' => 'app', 'roots' => ['teams/{team}/{service}'], 'stacks' => [stack] } }
  let(:config_hash) { { 'services' => [service] } }
  let(:config) { Entities::WorkflowConfig.new(config_hash) }
  let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: config) }
  let(:changed_files) { ['teams/platform/demo/aws/production/main.tf'] }
  let(:file_client) { instance_double(Infrastructure::FileSystemClient, get_changed_files: changed_files) }
  subject(:use_case) { described_class.new(file_client: file_client, config_client: config_client) }

  def services
    result = use_case.execute
    expect(result).to be_success
    result.services_detected
  end

  it 'omits services whose only match satisfies every exclusion condition' do
    expect(services).to eq([])
  end

  it 'keeps services with a non-excluded environment match' do
    changed_files << 'teams/platform/demo/aws/develop/main.tf'
    result = use_case.execute(base_ref: 'base', head_ref: 'head')
    expect(result.data.keys).to contain_exactly(:deploy_labels, :changed_files, :services_detected)
    expect(result.deploy_labels.map(&:to_s)).to eq(['deploy:demo'])
    expect(result.changed_files).to eq(changed_files)
    expect(file_client).to have_received(:get_changed_files).with(base_ref: 'base', head_ref: 'head')
  end

  it 'detects shared files next to declared environment directories' do
    changed_files.replace(['teams/platform/demo/aws/modules/main.tf'])
    expect(services).to eq(['demo'])
  end

  it 'detects files outside every stack path' do
    changed_files.replace(['teams/platform/demo/Makefile'])
    expect(services).to eq(['demo'])
  end

  it 'keeps omitting files whose stack targets are all excluded' do
    changed_files.replace(['teams/platform/demo/aws/production/main.tf'])
    expect(services).to eq([])
  end

  it 'skips ignored files' do
    service['ignore'] = ['**/README.md']
    changed_files.replace(['teams/platform/demo/README.md', 'teams/platform/demo/aws/README.md'])
    expect(services).to eq([])
  end

  it 'treats a trailing /** as every file below the directory' do
    service['ignore'] = ['docs/**']
    changed_files.replace(['teams/platform/demo/docs/a/b.md'])
    expect(services).to eq([])
  end

  it 'treats files under a dot path as inside the stack' do
    service['stacks'] = [{ 'id' => 'container', 'path' => '.', 'exclude' => [{ 'service' => 'demo' }] }]
    changed_files.replace(['teams/platform/demo/Dockerfile'])
    expect(services).to eq([])
  end

  it 'deduplicates services detected through overlapping roots' do
    config_hash['services'] << { 'id' => 'other', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'kustomize', 'path' => 'k8s/{environment}' }] }
    changed_files.replace(['teams/platform/demo/Makefile'])
    expect(services).to eq(['demo'])
  end

  it 'treats undeclared environment directories as shared files' do
    changed_files.replace(['teams/platform/demo/aws/preview/main.tf'])
    expect(services).to eq(['demo'])
  end

  it 'evaluates every environment for paths without environment' do
    stack['path'] = 'aws'
    expect(services).to eq(['demo'])
    stack['exclude'] = [{ 'environment' => 'develop' }, { 'environment' => 'production' }]
    allow(config_client).to receive(:load_workflow_config).and_return(Entities::WorkflowConfig.new(config_hash))
    expect(services).to eq([])
  end

  it 'keeps services with a non-excluded stack match' do
    service['stacks'] << { 'id' => 'container', 'path' => '.' }
    expect(services).to eq(['demo'])
  end

  it 'does not exclude paths missing custom captures' do
    service['roots'] << 'dystopia/{service}'
    changed_files << 'dystopia/demo/aws/production/main.tf'
    expect(services).to eq(['demo'])
  end

  it 'detects common stacks with null environment' do
    config_hash['services'] = [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.', 'exclude' => [{ 'service' => 'demo', 'environment' => nil }] }] }]
    changed_files.replace(['dystopia/demo/main.rb', 'dystopia/api/main.rb'])
    expect(services).to eq(['api'])
  end

  it 'ignores files placed at the service position' do
    config_hash['services'] = [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }]
    changed_files.replace(['dystopia/README.md', 'dystopia/api/main.rb'])
    expect(services).to eq(['api'])
  end

  it 'treats files placed at the environment position as shared files' do
    config_hash['services'] = [{ 'id' => 'app', 'roots' => ['dystopia/{service}'], 'stacks' => [{ 'id' => 'kubernetes', 'path' => 'kubernetes/overlays/{environment}' }] }]
    changed_files.replace(['dystopia/web/kubernetes/overlays/README.md', 'dystopia/api/kubernetes/overlays/develop/kustomization.yaml'])
    expect(services).to contain_exactly('web', 'api')
  end

  it 'uses AND within conditions and OR across conditions' do
    stack['exclude'] = [{ 'team' => 'platform', 'service' => 'demo' }, { 'team' => 'sandbox' }]
    changed_files.replace(['teams/platform/api/aws/develop/main.tf', 'teams/sandbox/api/aws/develop/main.tf', 'teams/platform/demo/aws/develop/main.tf'])
    expect(services).to eq(['api'])
  end

  it 'detects deleted file paths without checking filesystem existence' do
    changed_files.replace(['teams/absent/unregistered/aws/develop/deleted.tf'])
    expect(file_client).not_to receive(:resolve_directories)
    expect(services).to eq(['unregistered'])
  end

  it 'captures inferred environments from changed paths including deleted files' do
    stack.delete('environments')
    stack['exclude'] = [{ 'environment' => 'production' }]
    changed_files.replace(['teams/platform/demo/aws/production/deleted.tf', 'teams/platform/api/aws/preview/deleted.tf'])
    expect(file_client).not_to receive(:resolve_directories)
    expect(services).to eq(['api'])
  end

  it 'deduplicates matches for files paths and stacks' do
    service['roots'] << service['roots'].first
    changed_files.replace(['teams/platform/api/aws/develop/main.tf', 'teams/platform/api/aws/develop/vars.tf'])
    expect(services).to eq(['api'])
  end

  it 'ignores hidden services' do
    changed_files.replace(['teams/platform/.hidden/aws/develop/main.tf'])
    expect(services).to eq([])
  end

  [false, true].each do |reverse|
    it "rejects conflicting captures before exclusions with reversed paths #{reverse}" do
      roots = ['teams/{team}/{service}/aws', 'teams/{product}/{service}/aws']
      roots.reverse! if reverse
      config_hash['services'] = [{ 'id' => 'app', 'roots' => roots, 'stacks' => [{ 'id' => 'terragrunt', 'path' => '.', 'exclude' => [{ 'team' => 'platform' }] }] }]
      result = use_case.execute
      expect(result).to be_failure
      expect(result.error_message).to include('Conflicting captures', 'teams/platform/demo/aws')
      expect(result.data).not_to have_key(:deploy_labels)
    end
  end

  it 'returns successful empty results for unrelated changes' do
    changed_files.replace(['README.md'])
    expect(services).to eq([])
  end

  it 'returns failures for git errors' do
    allow(file_client).to receive(:get_changed_files).and_raise('git error')
    expect(use_case.execute.error_message).to include('git error')
  end

  it 'builds labels with the configured prefix' do
    config_hash['labels'] = { 'prefix' => 'release/' }
    changed_files.replace(['teams/platform/demo/aws/develop/main.tf'])
    expect(use_case.execute.deploy_labels.map(&:to_s)).to eq(['release/demo'])
  end
end
