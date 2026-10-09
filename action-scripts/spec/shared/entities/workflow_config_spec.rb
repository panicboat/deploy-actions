require 'spec_helper'

RSpec.describe Entities::WorkflowConfig do
  let(:stack) do
    {
      'name' => 'terragrunt',
      'paths' => ['dystopia/{service}/aws/{environment}'],
      'environments' => { 'develop' => { 'aws_region' => 'ap-northeast-1' }, 'production' => {} }
    }
  end
  let(:config_hash) { { 'stacks' => [stack] } }
  subject(:config) { described_class.new(config_hash) }

  it 'resolves omitted identities and environment names' do
    config_hash['stacks'] << { 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => {} }
    expect(config.stacks.map { |entry| entry['id'] }).to eq(%w[terragrunt container])
    expect(config.environment_names).to eq(%w[develop production])
    expect(config.stacks.last['attributes']).to eq({})
    expect(config.stacks.first['exclude']).to eq([])
  end

  it 'collects environment names from every stack without duplicates' do
    config_hash['stacks'] << {
      'name' => 'kubernetes', 'paths' => ['kubernetes/{service}'],
      'environments' => { 'production' => {}, 'preview' => {} }
    }
    expect(config.environment_names).to eq(%w[develop production preview])
  end

  it 'normalizes relative paths without changing the input' do
    stack['paths'] = ['./dystopia/./{service}/aws/{environment}/']
    expect(config.stacks.first['paths']).to eq(['dystopia/{service}/aws/{environment}'])
    expect(stack['paths']).to eq(['./dystopia/./{service}/aws/{environment}/'])
    expect(stack).not_to have_key('id')
  end

  it 'preserves attributes with different keys and value types' do
    stack['environments']['production'] = { 'token' => nil, 'enabled' => false, 'count' => 2, 'regions' => ['west'] }
    expect(config.stacks.first['environments']).to eq(
      'develop' => { 'aws_region' => 'ap-northeast-1' },
      'production' => { 'token' => nil, 'enabled' => false, 'count' => 2, 'regions' => ['west'] }
    )
  end

  it 'accepts repeated placeholders' do
    stack['paths'] = ['teams/{team}/{service}/{team}/aws/{environment}']
    expect { config }.not_to raise_error
  end

  it 'accepts environment discovery without an environment or attribute map' do
    stack.delete('environments')
    stack['exclude'] = [{ 'environment' => 'preview' }]
    expect { config }.not_to raise_error
    expect(config.stacks.first).not_to have_key('attributes')
    expect(config.stacks.first).not_to have_key('environments')
  end

  [nil, '', 1, [], 'a/b', '.', '..'].each do |value|
    it "rejects invalid inferred environment conditions #{value.inspect}" do
      stack.delete('environments')
      stack['exclude'] = [{ 'environment' => value }]
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].environment/)
    end
  end

  it 'requires environment placeholders when neither attribute map is specified' do
    stack.delete('environments')
    stack['paths'] = ['dystopia/{service}/aws']
    expect { config }.to raise_error(ArgumentError, /requires.*environment/)
  end

  it 'requires an environment placeholder in every inferred path' do
    stack.delete('environments')
    stack['paths'] << 'other/{service}/aws'
    expect { config }.to raise_error(ArgumentError, /paths\[1\]/)
  end

  it 'rejects attribute templates that cannot be resolved by every path' do
    stack['paths'] << 'teams/{team}/{service}/aws/{environment}'
    stack['environments']['develop']['repository'] = 'ghcr.io/{team}/{service}'
    expect { config }.to raise_error(ArgumentError, /team/)
  end

  it 'rejects environment templates for common attributes' do
    stack.replace('name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => { 'repository' => 'ghcr.io/{service}/{environment}' })
    expect { config }.to raise_error(ArgumentError, /environment/)
  end

  it 'validates placeholders inside nested attribute values' do
    stack['environments']['develop']['settings'] = { 'images' => ['ghcr.io/{unknown}/{service}'] }
    expect { config }.to raise_error(ArgumentError, /unknown/)
  end

  it 'matches all conditions in a rule and any rule in the array' do
    stack['paths'] = ['{team}/{service}/aws/{environment}']
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
    stack['paths'] = ['dystopia/{service}/aws']
    stack['exclude'] = [{ 'environment' => 'production' }]
    %w[demo api].each do |service|
      expect(config.excluded?(config.stacks.first, 'service' => service, 'environment' => 'production')).to be(true)
      expect(config.excluded?(config.stacks.first, 'service' => service, 'environment' => 'develop')).to be(false)
    end
  end

  it 'allows custom keys from the union of stack paths without matching missing captures' do
    stack['paths'] << 'teams/{team}/{service}/aws/{environment}'
    stack['exclude'] = [{ 'team' => 'sandbox' }]
    expect(config.excluded?(config.stacks.first, 'service' => 'demo', 'environment' => 'production')).to be(false)
  end

  it 'allows another stack to use an attribute named after a placeholder' do
    stack['paths'] = ['teams/{team}/{service}/aws/{environment}']
    config_hash['stacks'] << { 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => { 'team' => 'platform' } }
    expect { config }.not_to raise_error
  end

  context 'with common targets' do
    let(:stack) { { 'name' => 'container', 'paths' => ['dystopia/{service}'], 'attributes' => {} } }

    it 'derives an empty environment list' do
      expect(config.environment_names).to eq([])
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
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].environment/)
    end

    it 'rejects environment placeholders' do
      stack['paths'] = ['dystopia/{service}/{environment}']
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].paths\[0\]/)
    end

    [nil, [], 'value', { '' => true }, { 1 => true }, { 'stack_id' => 'other' }].each do |value|
      it "rejects invalid common attributes #{value.inspect}" do
        stack['attributes'] = value
        expect { config }.to raise_error(ArgumentError, /stacks\[0\].attributes/)
      end
    end
  end

  [nil, [], {}, { 'stacks' => nil }, { 'stacks' => {} }, { 'stacks' => [] }, { 'stacks' => [nil] }].each do |value|
    it "rejects invalid configuration structure #{value.inspect}" do
      expect { described_class.new(value) }.to raise_error(ArgumentError, /configuration|stacks/)
    end
  end

  %w[services environments stack_conventions unknown].each do |key|
    it "rejects the unknown top-level field #{key}" do
      config_hash[key] = []
      expect { config }.to raise_error(ArgumentError, /#{key}/)
    end
  end

  %w[root directory required_attributes unknown].each do |key|
    it "rejects the unknown stack field #{key}" do
      stack[key] = 'value'
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].#{key}/)
    end
  end

  {
    'name' => [nil, '', 1],
    'id' => [nil, '', 1],
    'paths' => [nil, [], 'path', [nil], ['']],
    'environments' => [nil, [], {}, { 'develop' => [] }, { '' => {} }, { 1 => {} }, { 'a/b' => {} }, { '.' => {} }, { '..' => {} }],
    'exclude' => [nil, {}, [nil], [{}]]
  }.each do |key, values|
    values.each do |value|
      it "rejects invalid #{key} #{value.inspect}" do
        stack[key] = value
        expect { config }.to raise_error(ArgumentError, /stacks\[0\].#{key}/)
      end
    end
  end

  [
    '/dystopia/{service}', 'dystopia/../{service}', 'dystopia/aws',
    'dystopia/{Service}', 'dystopia/{service}/{my-team}', 'dystopia/{service}/{team',
    'dystopia/{{service}}', 'dystopia/{service}/{stack}',
    'dystopia/{service}/{stack_id}', 'dystopia/{service}/{working_directory}'
  ].each do |pattern|
    it "rejects invalid path #{pattern}" do
      stack['paths'] = [pattern]
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].paths\[0\]/)
    end
  end

  [nil, 1, [], '', 'a/b', '.', '..', '.hidden'].each do |value|
    it "rejects invalid service conditions #{value.inspect}" do
      stack['exclude'] = [{ 'service' => value }]
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].service/)
    end
  end

  [nil, 'preview', 1].each do |value|
    it "rejects undeclared environment conditions #{value.inspect}" do
      stack['exclude'] = [{ 'environment' => value }]
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].environment/)
    end
  end

  %w[team aws_region].each do |key|
    it "rejects undeclared exclusion keys #{key}" do
      stack['exclude'] = [{ key => 'value' }]
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].#{key}/)
    end
  end

  it 'does not permit placeholders declared in another stack as exclusion keys' do
    config_hash['stacks'] << { 'name' => 'container', 'paths' => ['teams/{team}/{service}'], 'attributes' => {} }
    stack['exclude'] = [{ 'team' => 'sandbox' }]
    expect { config }.to raise_error(ArgumentError, /stacks\[0\].exclude\[0\].team/)
  end

  it 'rejects attribute inheritance between common and environment attributes' do
    stack['attributes'] = {}
    expect { config }.to raise_error(ArgumentError, /stacks\[0\]/)
  end

  it 'rejects identities shared by separate definitions' do
    stack['id'] = 'aws'
    config_hash['stacks'] << { 'name' => 'aws', 'paths' => ['other/{service}'], 'attributes' => {} }
    expect { config }.to raise_error(ArgumentError, /stacks\[1\].id/)
  end

  it 'accepts distinct identities for the same stack kind' do
    stack['id'] = 'aws'
    config_hash['stacks'] << { 'name' => 'terragrunt', 'id' => 'stripe', 'paths' => ['other/{service}'], 'attributes' => {} }
    expect(config.stacks.map { |entry| entry['id'] }).to eq(%w[aws stripe])
  end

  ['', 1, 'service', 'environment', 'stack', 'stack_id', 'working_directory'].each do |key|
    it "rejects invalid environment attribute keys #{key.inspect}" do
      stack['environments']['production'] = { key => 'value' }
      expect { config }.to raise_error(ArgumentError, /stacks\[0\].environments/)
    end
  end

  it 'checks placeholder collisions against attributes in every environment' do
    stack['paths'] = ['teams/{team}/{service}/aws/{environment}']
    stack['environments']['production'] = { 'team' => 'platform' }
    expect { config }.to raise_error(ArgumentError, /stacks\[0\].paths\[0\]/)
  end
end
