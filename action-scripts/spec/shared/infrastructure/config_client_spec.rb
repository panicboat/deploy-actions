require 'spec_helper'
require 'tempfile'

RSpec.describe Infrastructure::ConfigClient do
  let(:content) do
    { 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [{ 'id' => 'container', 'path' => '.', 'attributes' => { 'repository' => 'registry.example.com/app' } }] }] }.to_yaml
  end
  let(:file) { Tempfile.new(['workflow-config', '.yaml']) }
  let(:client) { described_class.new(config_path: file.path) }

  before do
    file.write(content)
    file.flush
  end

  after { file.close! }

  it 'loads a configuration from the requested file' do
    config = client.load_workflow_config
    expect(config.stacks.first).to have_attributes(id: 'container', paths: ['apps/{service}'])
    expect(config.declared_environment_names).to eq([])
  end

  it 'keeps the parsed configuration cached until explicitly cleared' do
    first = client.load_workflow_config
    File.write(file.path, content.sub('registry.example.com/app', 'registry.example.com/other'))
    expect(client.load_workflow_config).to be(first)
    expect(client.load_workflow_config.stacks.first.attributes).to eq('repository' => 'registry.example.com/app')
    client.clear_cache
    expect(client.load_workflow_config.stacks.first.attributes).to eq('repository' => 'registry.example.com/other')
  end

  it 'requires a configuration path' do
    expect { described_class.new }.to raise_error(ArgumentError, /config_path/)
  end

  it 'loads anchors and merge keys' do
    File.write(file.path, <<~YAML)
      profiles:
        aws-develop: &aws_develop
          aws_region: ap-northeast-1
      services:
        - id: app
          roots: ["apps/{service}"]
          stacks:
            - id: aws
              path: "aws/{environment}"
              environments:
                develop:
                  <<: *aws_develop
                  gcp_project: foo
    YAML
    config = described_class.new(config_path: file.path).load_workflow_config
    expect(config.stacks.first.target_attributes('develop')).to eq('aws_region' => 'ap-northeast-1', 'gcp_project' => 'foo')
  end

  it 'reports the missing file path' do
    expect { described_class.new(config_path: "#{file.path}.missing").load_workflow_config }.to raise_error(/not found.*\.missing/)
  end

  it 'reports permission errors with the file path' do
    allow(File).to receive(:read).with(file.path).and_raise(Errno::EACCES)
    expect { client.load_workflow_config }.to raise_error(/Permission denied.*#{Regexp.escape(file.path)}/)
  end

  context 'with malformed YAML' do
    let(:content) { "services: [\n  {id: app\n" }

    it 'reports the YAML line number' do
      expect { client.load_workflow_config }.to raise_error(/YAML.*line \d+/)
    end
  end

  context 'with an invalid configuration' do
    let(:content) { "services:\n  - id: app\n    roots: []\n" }

    it 'preserves the validation position and file path' do
      expect { client.load_workflow_config }.to raise_error(/#{Regexp.escape(file.path)}.*services\[0\].roots/)
    end
  end

  context 'with an empty configuration file' do
    let(:content) { '' }

    it 'reports a configuration error' do
      expect { client.load_workflow_config }.to raise_error(/configuration/i)
    end
  end
end
