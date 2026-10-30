require 'spec_helper'

RSpec.describe Entities::WorkflowConfig do
  let(:stack) do
    {
      'id' => 'aws',
      'path' => 'aws/{environment}',
      'environments' => { 'develop' => { 'aws_region' => 'ap-northeast-1' }, 'production' => {} }
    }
  end
  let(:service) { { 'id' => 'app', 'roots' => ['dystopia/{service}', 'system-components/{service}'], 'stacks' => [stack] } }
  let(:config_hash) { { 'services' => [service] } }
  subject(:config) { described_class.new(config_hash) }

  it 'joins every root with the stack path' do
    expect(config.stacks.first['paths']).to eq(['dystopia/{service}/aws/{environment}', 'system-components/{service}/aws/{environment}'])
    expect(config.stacks.first['service_id']).to eq('app')
  end

  it 'uses the root itself for a dot path and marks it common' do
    service['stacks'] = [{ 'id' => 'container', 'path' => './', 'attributes' => { 'type' => 'container' } }]
    expect(config.stacks.first).to include('paths' => ['dystopia/{service}', 'system-components/{service}'], 'common' => true, 'attributes' => { 'type' => 'container' })
  end

  it 'gives discovered stacks their attributes' do
    service['stacks'] = [{ 'id' => 'kustomize', 'path' => 'overlays/{environment}', 'attributes' => { 'type' => 'kustomize' } }]
    expect(config.stacks.first).to include('common' => false, 'attributes' => { 'type' => 'kustomize' })
    expect(config.stacks.first).not_to have_key('environments')
  end

  it 'merges stack attributes, profiles, and inline attributes into each environment' do
    config_hash['profiles'] = { 'aws-develop' => { 'iam_role_plan' => 'plan' } }
    stack['attributes'] = { 'type' => 'terragrunt' }
    stack['environments']['develop'] = { 'use' => ['aws-develop'], 'gcp_project' => 'foo-develop' }
    expect(config.target_attributes(config.stacks.first, 'develop')).to eq('type' => 'terragrunt', 'iam_role_plan' => 'plan', 'gcp_project' => 'foo-develop')
  end

  it 'returns the stack attributes as target attributes without environments' do
    service['stacks'] = [{ 'id' => 'kustomize', 'path' => 'overlays/{environment}', 'attributes' => { 'type' => 'kustomize' } }]
    expect(config.target_attributes(config.stacks.first, 'develop')).to eq('type' => 'kustomize')
  end

  it 'rejects an attribute defined twice' do
    config_hash['profiles'] = { 'a' => { 'k' => 1 }, 'b' => { 'k' => 2 } }
    stack['environments']['develop'] = { 'use' => %w[a b] }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments\.develop: attribute 'k' is defined by both profile 'a' and profile 'b'/)
  end

  it 'rejects an inline attribute that is also a stack attribute' do
    stack['attributes'] = { 'type' => 'terragrunt' }
    stack['environments']['develop'] = { 'type' => 'other' }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments\.develop: attribute 'type' is defined by both/)
  end

  it 'rejects an undefined profile' do
    stack['environments']['develop'] = { 'use' => ['missing'] }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments\.develop\.use\[0\]: profile 'missing' is not defined/)
  end

  it 'rejects use in stack attributes' do
    config_hash['profiles'] = { 'p' => {} }
    stack['attributes'] = { 'use' => ['p'] }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.attributes\.use: use can only be set in environments/)
  end

  it 'rejects use in profiles' do
    config_hash['profiles'] = { 'p' => { 'use' => 'x' } }
    stack['environments']['develop'] = { 'use' => ['p'] }
    expect { config }.to raise_error(ArgumentError, /profiles\.p\.use: use can only be set in environments/)
  end

  it 'allows unused profiles' do
    config_hash['profiles'] = { 'unused' => {} }
    expect { config }.not_to raise_error
  end

  [nil, [], 'value', { 'develop' => nil }, { 'develop' => { 'stack' => 'x' } }].each do |value|
    it "rejects invalid profiles #{value.inspect}" do
      config_hash['profiles'] = value
      expect { config }.to raise_error(ArgumentError, /profiles/)
    end
  end

  [nil, [], 'aws-develop', [nil], ['']].each do |value|
    it "rejects invalid use #{value.inspect}" do
      stack['environments']['develop'] = { 'use' => value }
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments\.develop\.use/)
    end
  end

  it 'rejects {environment} in roots' do
    service['roots'] = ['envs/{environment}/{service}']
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.roots\[0\]: \{environment\} cannot be used in roots/)
  end

  it 'rejects {service} in stack paths' do
    stack['path'] = '{service}/aws'
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.path: \{service\} cannot be used in stack paths/)
  end

  it 'rejects placeholders missing from some roots' do
    service['roots'] = ['aws/{service}', 'gcp/{project}/{service}']
    stack['attributes'] = { 'project' => '{project}-x' }
    expect { config }.to raise_error(ArgumentError, /placeholders project cannot be resolved/)
  end

  it 'rejects profile templates that cannot be resolved by the stack using it' do
    config_hash['profiles'] = { 'gcp' => { 'gcp_project' => '{project}-develop' } }
    stack['environments']['develop'] = { 'use' => ['gcp'] }
    expect { config }.to raise_error(ArgumentError, /profiles\.gcp\.gcp_project: placeholders project cannot be resolved by services\[0\]\.roots\[0\]/)
  end

  it 'rejects duplicate stack identities across services' do
    config_hash['services'] << { 'id' => 'other', 'roots' => ['other/{service}'], 'stacks' => [{ 'id' => 'aws', 'path' => '.' }] }
    expect { config }.to raise_error(ArgumentError, /services\[1\]\.stacks\[0\]\.id: duplicate identity 'aws'/)
  end

  it 'rejects duplicate service identities' do
    config_hash['services'] << { 'id' => 'app', 'roots' => ['other/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }
    expect { config }.to raise_error(ArgumentError, /services\[1\]\.id: duplicate identity 'app'/)
  end

  it 'rejects the legacy top-level stacks' do
    expect { described_class.new('stacks' => []) }.to raise_error(ArgumentError, /\AConfiguration validation failed: configuration\.stacks: unknown field; use services\z/)
  end

  it 'exposes services with normalized roots and ignore patterns' do
    service['roots'] = ['./dystopia//{service}/']
    service['ignore'] = ['**/README.md']
    expect(config.services).to eq([
      { 'id' => 'app', 'roots' => ['dystopia/{service}'], 'ignore' => ['**/README.md'], 'stacks' => config.stacks }
    ])
  end

  it 'normalizes ignore patterns without changing the input' do
    service['ignore'] = ['./docs/**', './/**/README.md']
    expect(config.services.first['ignore']).to eq(['docs/**', '**/README.md'])
    expect(config.ignored?(config.services.first, 'docs/a/b.md')).to be(true)
    expect(service['ignore']).to eq(['./docs/**', './/**/README.md'])
  end

  it 'rejects absolute ignore patterns' do
    service['ignore'] = ['**/README.md', '/docs/**']
    expect { config }.to raise_error(ArgumentError, %r{services\[0\]\.ignore\[1\]: must be relative})
  end

  it 'rejects ignore patterns with parent-directory segments' do
    service['ignore'] = ['docs/../aws/**']
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.ignore\[0\]: must not contain parent-directory segments/)
  end

  it 'defaults ignore to an empty array and accepts an empty array' do
    expect(config.services.first['ignore']).to eq([])
    service['ignore'] = []
    expect(described_class.new(config_hash).services.first['ignore']).to eq([])
  end

  describe '#ignored?' do
    def ignored?(patterns, relative_path)
      service['ignore'] = patterns
      fresh = described_class.new(config_hash)
      fresh.ignored?(fresh.services.first, relative_path)
    end

    it 'matches nothing without ignore patterns' do
      expect(config.ignored?(config.services.first, 'README.md')).to be(false)
    end

    it 'matches zero or more directories with **/' do
      expect(ignored?(['**/README.md'], 'README.md')).to be(true)
      expect(ignored?(['**/README.md'], 'aws/modules/README.md')).to be(true)
    end

    it 'does not let * cross directories' do
      expect(ignored?(['*.md'], 'NOTES.md')).to be(true)
      expect(ignored?(['*.md'], 'aws/NOTES.md')).to be(false)
    end

    it 'matches every file below a directory with a trailing /**' do
      expect(ignored?(['docs/**'], 'docs/a.md')).to be(true)
      expect(ignored?(['docs/**'], 'docs/a/b.md')).to be(true)
      expect(ignored?(['docs/**'], 'aws/docs/a.md')).to be(false)
    end

    it 'matches files starting with a dot' do
      expect(ignored?(['*'], '.terraform-version')).to be(true)
      expect(ignored?(['**/*.md'], '.github/a.md')).to be(true)
    end

    it 'matches when any pattern matches' do
      expect(ignored?(['*.txt', '**/*.md'], 'aws/a.md')).to be(true)
      expect(ignored?(['*.txt', '**/*.md'], 'aws/main.tf')).to be(false)
    end
  end

  [nil, 'README.md', {}, [nil], [''], [1]].each do |value|
    it "rejects invalid ignore #{value.inspect}" do
      service['ignore'] = value
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.ignore/)
    end
  end

  it 'lists stacks of every service in order' do
    config_hash['services'] << { 'id' => 'kubernetes', 'roots' => ['kubernetes/{service}'], 'stacks' => [{ 'id' => 'helmfile', 'path' => '{environment}' }] }
    expect(config.stacks.map { |entry| [entry['service_id'], entry['id']] }).to eq([%w[app aws], %w[kubernetes helmfile]])
  end

  it 'collects environment names from every stack without duplicates' do
    service['stacks'] << { 'id' => 'kubernetes', 'path' => 'kubernetes', 'environments' => { 'production' => {}, 'preview' => {} } }
    expect(config.environment_names).to eq(%w[develop production preview])
  end

  it 'normalizes relative paths without changing the input' do
    stack['path'] = './aws/./{environment}/'
    expect(config.stacks.first['path']).to eq('aws/{environment}')
    expect(config.stacks.first['paths'].first).to eq('dystopia/{service}/aws/{environment}')
    expect(stack['path']).to eq('./aws/./{environment}/')
    expect(stack).not_to have_key('service_id')
  end

  it 'normalizes a dot path to an empty path' do
    stack['path'] = '.'
    expect(config.stacks.first['path']).to eq('')
  end

  it 'preserves attributes with different keys and value types' do
    stack['environments']['production'] = { 'token' => nil, 'enabled' => false, 'count' => 2, 'regions' => ['west'] }
    expect(config.stacks.first['environments']).to eq(
      'develop' => { 'aws_region' => 'ap-northeast-1' },
      'production' => { 'token' => nil, 'enabled' => false, 'count' => 2, 'regions' => ['west'] }
    )
  end

  it 'accepts repeated placeholders' do
    service['roots'] = ['teams/{team}/{service}']
    stack['path'] = '{team}/aws/{environment}'
    expect { config }.not_to raise_error
  end

  it 'accepts environment discovery without environments or attributes' do
    stack.delete('environments')
    stack['exclude'] = [{ 'environment' => 'preview' }]
    expect { config }.not_to raise_error
    expect(config.stacks.first).to include('common' => false, 'attributes' => {}, 'exclude' => [{ 'environment' => 'preview' }])
    expect(config.stacks.first).not_to have_key('environments')
  end

  [nil, '', 1, [], 'a/b', '.', '..'].each do |value|
    it "rejects invalid inferred environment conditions #{value.inspect}" do
      stack.delete('environments')
      stack['exclude'] = [{ 'environment' => value }]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.environment/)
    end
  end

  it 'allows environment templates in stack attributes when environments are declared' do
    stack['path'] = 'aws'
    stack['attributes'] = { 'state' => '{service}-{environment}' }
    expect { config }.not_to raise_error
    expect(config.stacks.first['common']).to be(false)
  end

  it 'rejects attribute templates that cannot be resolved by every root' do
    service['roots'] << 'teams/{team}/{service}'
    stack['environments']['develop']['repository'] = 'ghcr.io/{team}/{service}'
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments\.develop\.repository: placeholders team cannot be resolved/)
  end

  it 'rejects environment templates for common stacks' do
    service['stacks'] = [{ 'id' => 'container', 'path' => '.', 'attributes' => { 'repository' => 'ghcr.io/{service}/{environment}' } }]
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.attributes\.repository: placeholders environment/)
  end

  it 'validates placeholders inside nested attribute values' do
    stack['environments']['develop']['settings'] = { 'images' => ['ghcr.io/{unknown}/{service}'] }
    expect { config }.to raise_error(ArgumentError, /unknown/)
  end

  it 'matches all conditions in a rule and any rule in the array' do
    service['roots'] = ['{team}/{service}']
    stack['exclude'] = [
      { 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' },
      { 'team' => 'sandbox' }
    ]
    entry = config.stacks.first
    expect(config.excluded?(entry, 'team' => 'platform', 'service' => 'demo', 'environment' => 'production')).to be(true)
    expect(config.excluded?(entry, 'team' => 'platform', 'service' => 'demo', 'environment' => 'develop')).to be(false)
    expect(config.excluded?(entry, 'team' => 'platform', 'service' => 'api', 'environment' => 'production')).to be(false)
    expect(config.excluded?(entry, 'team' => 'sandbox', 'service' => 'api', 'environment' => 'develop')).to be(true)
    expect(config.excluded?(entry, 'service' => 'demo', 'environment' => 'production')).to be(false)
  end

  it 'matches a service condition across environments' do
    stack['exclude'] = [{ 'service' => 'demo' }]
    %w[develop production].each do |environment|
      expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'environment' => environment)).to be(true)
      expect(config.excluded?(config.stacks.first, 'service' => 'api', 'environment' => environment)).to be(false)
    end
  end

  it 'matches an environment condition when the path has no environment' do
    stack['path'] = 'aws'
    stack['exclude'] = [{ 'environment' => 'production' }]
    %w[demo api].each do |name|
      expect(config.excluded?(config.stacks.first, 'service' => name, 'environment' => 'production')).to be(true)
      expect(config.excluded?(config.stacks.first, 'service' => name, 'environment' => 'develop')).to be(false)
    end
  end

  it 'allows custom keys from the union of roots without matching missing captures' do
    service['roots'] << 'teams/{team}/{service}'
    stack['exclude'] = [{ 'team' => 'sandbox' }]
    expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'environment' => 'production')).to be(false)
  end

  it 'allows custom keys from the stack path' do
    stack['path'] = '{region}/{environment}'
    stack['exclude'] = [{ 'region' => 'us-east-1' }]
    expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'region' => 'us-east-1', 'environment' => 'develop')).to be(true)
  end

  it 'allows another stack to use an attribute named after a placeholder' do
    stack['path'] = '{team}/aws/{environment}'
    service['stacks'] << { 'id' => 'container', 'path' => '.', 'attributes' => { 'team' => 'platform' } }
    expect { config }.not_to raise_error
  end

  context 'with common targets' do
    let(:stack) { { 'id' => 'container', 'path' => '.' } }

    it 'derives an empty environment list and empty attributes' do
      expect(config.environment_names).to eq([])
      expect(config.stacks.first).to include('common' => true, 'attributes' => {})
    end

    it 'matches service rules without an environment condition' do
      stack['exclude'] = [{ 'service' => 'demo' }]
      expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'environment' => nil)).to be(true)
      expect(config.excluded?(config.stacks.first, 'service' => 'api', 'environment' => nil)).to be(false)
    end

    it 'distinguishes a null environment from an absent key' do
      stack['exclude'] = [{ 'environment' => nil }]
      expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'environment' => nil)).to be(true)
      expect(config.excluded?(config.stacks.first, 'service' => 'demo')).to be(false)
    end

    it 'rejects a named environment in a common exclusion' do
      stack['exclude'] = [{ 'environment' => 'production' }]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.environment/)
    end

    [nil, [], 'value', { '' => true }, { 1 => true }, { 'stack' => 'other' }].each do |value|
      it "rejects invalid stack attributes #{value.inspect}" do
        stack['attributes'] = value
        expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.attributes/)
      end
    end
  end

  [nil, [], {}, { 'services' => nil }, { 'services' => {} }, { 'services' => [] }, { 'services' => [nil] }].each do |value|
    it "rejects invalid configuration structure #{value.inspect}" do
      expect { described_class.new(value) }.to raise_error(ArgumentError, /configuration|services/)
    end
  end

  %w[stacks environments stack_conventions unknown].each do |key|
    it "rejects the unknown top-level field #{key}" do
      config_hash[key] = []
      expect { config }.to raise_error(ArgumentError, /configuration\.#{key}: unknown field/)
    end
  end

  %w[name paths root unknown].each do |key|
    it "rejects the unknown service field #{key}" do
      service[key] = 'value'
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.#{key}: unknown field/)
    end
  end

  %w[name paths root directory required_attributes unknown].each do |key|
    it "rejects the unknown stack field #{key}" do
      stack[key] = 'value'
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.#{key}: unknown field/)
    end
  end

  {
    'id' => [nil, '', 1],
    'roots' => [nil, [], 'path', [nil], ['']],
    'stacks' => [nil, [], {}, [nil]]
  }.each do |key, values|
    values.each do |value|
      it "rejects invalid service #{key} #{value.inspect}" do
        service[key] = value
        expect { config }.to raise_error(ArgumentError, /services\[0\]\.#{key}/)
      end
    end
  end

  {
    'id' => [nil, '', 1],
    'path' => [nil, '', 1, []],
    'environments' => [nil, [], {}, { 'develop' => [] }, { '' => {} }, { 1 => {} }, { 'a/b' => {} }, { '.' => {} }, { '..' => {} }],
    'exclude' => [nil, {}, [nil], [{}]]
  }.each do |key, values|
    values.each do |value|
      it "rejects invalid stack #{key} #{value.inspect}" do
        stack[key] = value
        expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.#{key}/)
      end
    end
  end

  [
    '/dystopia/{service}', 'dystopia/../{service}', 'dystopia/aws',
    'dystopia/{Service}', 'dystopia/{service}/{my-team}', 'dystopia/{service}/{team',
    'dystopia/{{service}}', 'dystopia/{service}/{stack}',
    'dystopia/{service}/{working_directory}'
  ].each do |pattern|
    it "rejects invalid root #{pattern}" do
      service['roots'] = [pattern]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.roots\[0\]/)
    end
  end

  [
    '/aws', 'aws/../{environment}', 'aws/{my-team}', 'aws/{team',
    'aws/{{environment}}', 'aws/{stack}', 'aws/{working_directory}'
  ].each do |pattern|
    it "rejects invalid stack path #{pattern}" do
      stack['path'] = pattern
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.path/)
    end
  end

  [nil, 1, [], '', 'a/b', '.', '..', '.hidden'].each do |value|
    it "rejects invalid service conditions #{value.inspect}" do
      stack['exclude'] = [{ 'service' => value }]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.service/)
    end
  end

  [nil, 'preview', 1].each do |value|
    it "rejects undeclared environment conditions #{value.inspect}" do
      stack['exclude'] = [{ 'environment' => value }]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.environment/)
    end
  end

  it 'reports an environment condition that the stack does not declare' do
    stack['exclude'] = [{ 'environment' => 'preview' }]
    expect { config }.to raise_error(ArgumentError, /exclude\[0\]\.environment: environment 'preview' is not declared in this stack/)
  end

  %w[team aws_region].each do |key|
    it "rejects undeclared exclusion keys #{key}" do
      stack['exclude'] = [{ key => 'value' }]
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.#{key}/)
    end
  end

  it 'does not permit placeholders declared in another service as exclusion keys' do
    config_hash['services'] << { 'id' => 'teams', 'roots' => ['teams/{team}/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.' }] }
    stack['exclude'] = [{ 'team' => 'sandbox' }]
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.exclude\[0\]\.team/)
  end

  ['', 1, 'service', 'environment', 'stack', 'working_directory'].each do |key|
    it "rejects invalid environment attribute keys #{key.inspect}" do
      stack['environments']['production'] = { key => 'value' }
      expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.environments/)
    end
  end

  it 'checks root placeholder collisions against attributes in every environment' do
    service['roots'] = ['teams/{team}/{service}']
    stack['environments']['production'] = { 'team' => 'platform' }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.roots\[0\]: placeholder 'team' collides/)
  end

  it 'checks path placeholder collisions against stack attributes' do
    stack['path'] = '{team}/{environment}'
    stack['attributes'] = { 'team' => 'platform' }
    expect { config }.to raise_error(ArgumentError, /services\[0\]\.stacks\[0\]\.path: placeholder 'team' collides/)
  end

  describe 'labels' do
    it 'defaults to the deploy prefix without extra prefixes' do
      expect(config.label_prefix).to eq('deploy:')
      expect(config.extra_label_prefixes).to eq([])
      expect(config.label_prefixes).to eq(['deploy:'])
    end

    it 'reads the prefix and extra prefixes including their separators' do
      config_hash['labels'] = { 'prefix' => 'env:prod:', 'extra_prefixes' => ['manual/', 'hotfix-'] }
      expect(config.label_prefix).to eq('env:prod:')
      expect(config.extra_label_prefixes).to eq(['manual/', 'hotfix-'])
      expect(config.label_prefixes).to eq(['env:prod:', 'manual/', 'hotfix-'])
    end

    it 'rejects the unknown labels field' do
      config_hash['labels'] = { 'unknown' => 'value' }
      expect { config }.to raise_error(ArgumentError, /labels.unknown/)
    end

    [nil, [], 'deploy:'].each do |value|
      it "rejects invalid labels structure #{value.inspect}" do
        config_hash['labels'] = value
        expect { config }.to raise_error(ArgumentError, /labels/)
      end
    end

    [nil, '', 1].each do |value|
      it "rejects invalid prefix #{value.inspect}" do
        config_hash['labels'] = { 'prefix' => value }
        expect { config }.to raise_error(ArgumentError, /labels.prefix/)
      end
    end

    [nil, 'manual/', {}, [nil], [''], [1]].each do |value|
      it "rejects invalid extra prefixes #{value.inspect}" do
        config_hash['labels'] = { 'extra_prefixes' => value }
        expect { config }.to raise_error(ArgumentError, /labels.extra_prefixes/)
      end
    end

    {
      'a duplicate of the prefix' => { 'extra_prefixes' => ['deploy:'] },
      'duplicate extra prefixes' => { 'extra_prefixes' => ['manual/', 'manual/'] },
      'an extra prefix starting with the prefix' => { 'extra_prefixes' => ['deploy:manual:'] },
      'a prefix starting with an extra prefix' => { 'prefix' => 'deploy-manual-', 'extra_prefixes' => ['deploy-'] }
    }.each do |description, labels|
      it "rejects #{description}" do
        config_hash['labels'] = labels
        expect { config }.to raise_error(ArgumentError, /labels: .*overlaps/)
      end
    end
  end
end
