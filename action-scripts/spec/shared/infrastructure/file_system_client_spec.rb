require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Infrastructure::FileSystemClient do
  subject(:client) { described_class.new }

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

  it 'resolves every matching directory in sorted order with exact context values' do
    %w[teams/sandbox/demo/aws/production teams/platform/demo/aws/production teams/platform/demo/aws/develop teams/platform/api/aws/production].each { |path| directory(path) }
    directory('teams/file/demo/aws')
    File.write(File.join(@root, 'teams/file/demo/aws/production'), '')
    expect(client.resolve_directories(pattern: 'teams/{team}/{service}/aws/{environment}', values: { 'service' => 'demo', 'environment' => 'production' })).to eq([
      { working_directory: 'teams/platform/demo/aws/production', captures: { 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' } },
      { working_directory: 'teams/sandbox/demo/aws/production', captures: { 'team' => 'sandbox', 'service' => 'demo', 'environment' => 'production' } }
    ])
  end

  it 'matches repeated placeholders only when their values agree' do
    directory('teams/platform/demo/platform')
    directory('teams/platform/demo/sandbox')
    expect(client.resolve_directories(pattern: 'teams/{team}/{service}/{team}').map { |match| match[:working_directory] }).to eq(['teams/platform/demo/platform'])
  end

  it 'treats glob characters as literals' do
    ['literal[1]', 'literal*', 'literal?', 'literal{a,b}', 'literal\\x'].each do |prefix|
      directory("#{prefix}/demo")
      expect(client.resolve_directories(pattern: "#{prefix}/{service}").map { |match| match[:working_directory] }).to eq(["#{prefix}/demo"])
    end
    directory('literal1/demo')
    expect(client.resolve_directories(pattern: 'literal[1]/{service}').length).to eq(1)
  end

  it 'ignores context keys absent from the pattern' do
    directory('dystopia/demo/aws')
    expect(client.resolve_directories(pattern: 'dystopia/{service}/aws', values: { 'service' => 'demo', 'environment' => 'production' })).to eq([
      { working_directory: 'dystopia/demo/aws', captures: { 'service' => 'demo' } }
    ])
  end

  it 'returns no matches for absent directories' do
    expect(client.resolve_directories(pattern: 'dystopia/{service}/aws')).to eq([])
  end

  it 'propagates directory enumeration errors' do
    allow(Dir).to receive(:glob).and_raise(Errno::EACCES)
    expect { client.resolve_directories(pattern: 'dystopia/{service}') }.to raise_error(Errno::EACCES)
  end

  it 'uses the source repository root' do
    expect(client.repository_root).to eq(@root)
  end

  it 'accepts git marker files' do
    FileUtils.rm_r(File.join(@root, '.git'))
    File.write(File.join(@root, '.git'), 'gitdir: elsewhere')
    expect(client.repository_root).to eq(@root)
  end

  it 'searches parent directories from the supplied start path' do
    ENV.delete('SOURCE_REPO_PATH')
    directory('nested/deep')
    expect(client.repository_root(start_path: File.join(@root, 'nested/deep'))).to eq(@root)
  end

  it 'resolves relative source paths from the supplied start path' do
    directory('nested')
    ENV['SOURCE_REPO_PATH'] = '..'
    expect(client.repository_root(start_path: File.join(@root, 'nested'))).to eq(@root)
  end

  it 'fails when no repository root exists' do
    FileUtils.rm_r(File.join(@root, '.git'))
    expect { client.repository_root(start_path: @root) }.to raise_error(/Could not find repository root/)
  end
end
