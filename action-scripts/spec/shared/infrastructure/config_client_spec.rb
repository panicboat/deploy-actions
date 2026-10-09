require 'spec_helper'
require 'tempfile'

RSpec.describe Infrastructure::ConfigClient do
  let(:content) { { 'stacks' => [{ 'name' => 'container', 'paths' => ['apps/{service}'], 'attributes' => { 'repository' => 'registry.example.com/app' } }] }.to_yaml }
  let(:file) { Tempfile.new(['workflow-config', '.yaml']) }
  let(:client) { described_class.new(config_path: file.path) }

  before do
    file.write(content)
    file.flush
  end

  after { file.close! }

  it 'loads a configuration from the requested file' do
    config = client.load_workflow_config
    expect(config.stacks.first).to include('id' => 'container', 'paths' => ['apps/{service}'])
    expect(config.environment_names).to eq([])
  end

  it 'keeps the parsed configuration cached until explicitly cleared' do
    first = client.load_workflow_config
    File.write(file.path, content.sub('registry.example.com/app', 'registry.example.com/other'))
    expect(client.load_workflow_config).to be(first)
    expect(client.load_workflow_config.stacks.first['attributes']).to eq('repository' => 'registry.example.com/app')
    client.clear_cache
    expect(client.load_workflow_config.stacks.first['attributes']).to eq('repository' => 'registry.example.com/other')
  end

  it 'uses the environment-specified path when no path is passed' do
    ENV['WORKFLOW_CONFIG_PATH'] = file.path
    expect(described_class.new.load_workflow_config.stacks.first['id']).to eq('container')
  end

  it 'reports the missing file path' do
    expect { described_class.new(config_path: "#{file.path}.missing").load_workflow_config }.to raise_error(/not found.*\.missing/)
  end

  it 'reports permission errors with the file path' do
    allow(File).to receive(:read).with(file.path).and_raise(Errno::EACCES)
    expect { client.load_workflow_config }.to raise_error(/Permission denied.*#{Regexp.escape(file.path)}/)
  end

  context 'with malformed YAML' do
    let(:content) { "stacks: [\n  {name: container\n" }

    it 'reports the YAML line number' do
      expect { client.load_workflow_config }.to raise_error(/YAML.*line \d+/)
    end
  end

  context 'with an invalid configuration' do
    let(:content) { "stacks:\n  - name: container\n    paths: []\n" }

    it 'preserves the validation position and file path' do
      expect { client.load_workflow_config }.to raise_error(/#{Regexp.escape(file.path)}.*stacks\[0\].paths/)
    end
  end

  context 'with an empty configuration file' do
    let(:content) { '' }

    it 'reports a configuration error' do
      expect { client.load_workflow_config }.to raise_error(/configuration/i)
    end
  end
end
