require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Infrastructure::DirectoryScanner do
  subject(:scanner) { described_class.new(repository_root: @root) }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  def directory(path)
    FileUtils.mkdir_p(File.join(@root, path))
  end

  it 'resolves every matching directory in sorted order with exact context values' do
    %w[teams/sandbox/demo/aws/production teams/platform/demo/aws/production teams/platform/demo/aws/develop teams/platform/api/aws/production].each { |path| directory(path) }
    directory('teams/file/demo/aws')
    File.write(File.join(@root, 'teams/file/demo/aws/production'), '')
    expect(scanner.resolve(pattern: 'teams/{team}/{service}/aws/{environment}', values: { 'service' => 'demo', 'environment' => 'production' })).to eq([
      { working_directory: 'teams/platform/demo/aws/production', captures: { 'team' => 'platform', 'service' => 'demo', 'environment' => 'production' } },
      { working_directory: 'teams/sandbox/demo/aws/production', captures: { 'team' => 'sandbox', 'service' => 'demo', 'environment' => 'production' } }
    ])
  end

  it 'matches repeated placeholders only when their values agree' do
    directory('teams/platform/demo/platform')
    directory('teams/platform/demo/sandbox')
    expect(scanner.resolve(pattern: 'teams/{team}/{service}/{team}').map { |match| match[:working_directory] }).to eq(['teams/platform/demo/platform'])
  end

  it 'treats glob characters as literals' do
    ['literal[1]', 'literal*', 'literal?', 'literal{a,b}', 'literal\\x'].each do |prefix|
      directory("#{prefix}/demo")
      expect(scanner.resolve(pattern: "#{prefix}/{service}").map { |match| match[:working_directory] }).to eq(["#{prefix}/demo"])
    end
    directory('literal1/demo')
    expect(scanner.resolve(pattern: 'literal[1]/{service}').length).to eq(1)
  end

  it 'ignores context keys absent from the pattern' do
    directory('dystopia/demo/aws')
    expect(scanner.resolve(pattern: 'dystopia/{service}/aws', values: { 'service' => 'demo', 'environment' => 'production' })).to eq([
      { working_directory: 'dystopia/demo/aws', captures: { 'service' => 'demo' } }
    ])
  end

  it 'returns no matches for absent directories' do
    expect(scanner.resolve(pattern: 'dystopia/{service}/aws')).to eq([])
  end

  it 'propagates actual permission errors for literal and placeholder directories' do
    directory('blocked/demo')
    path = File.join(@root, 'blocked')
    File.chmod(0, path)
    expect { Dir.children(path) }.to raise_error(Errno::EACCES)
    expect { scanner.resolve(pattern: 'blocked/{service}') }.to raise_error(Errno::EACCES)
    expect { scanner.resolve(pattern: '{team}/{service}') }.to raise_error(Errno::EACCES)
  ensure
    File.chmod(0o755, path) if path
  end

  it 'resolves dot-prefixed environments and arbitrary placeholders without dot entries' do
    directory('teams/.platform/demo/.preview')
    expect(scanner.resolve(pattern: 'teams/{team}/{service}/{environment}', values: { 'environment' => '.preview' })).to eq([
      { working_directory: 'teams/.platform/demo/.preview', captures: { 'team' => '.platform', 'service' => 'demo', 'environment' => '.preview' } }
    ])
  end

  it 'returns dot-prefixed services' do
    directory('teams/platform/.hidden/aws')
    expect(scanner.resolve(pattern: 'teams/{team}/{service}/aws')).to eq([
      { working_directory: 'teams/platform/.hidden/aws', captures: { 'team' => 'platform', 'service' => '.hidden' } }
    ])
  end

  it 'does not traverse repeated-placeholder mismatches or unselected services' do
    directory('teams/platform/sandbox/demo')
    path = File.join(@root, 'teams/platform/sandbox')
    File.chmod(0, path)
    expect(scanner.resolve(pattern: 'teams/{team}/{team}/{service}')).to eq([])
    expect(scanner.resolve(pattern: 'teams/{team}/{service}/{environment}', values: { 'service' => 'other' })).to eq([])
  ensure
    File.chmod(0o755, path) if path
  end

  it 'ignores dangling symlinks while preserving directory stat permission errors' do
    File.symlink(File.join(@root, 'absent'), File.join(@root, 'dangling'))
    expect(scanner.resolve(pattern: '{service}').map { |match| match[:working_directory] }).not_to include('dangling')
    directory('protected/demo')
    path = File.join(@root, 'protected')
    File.symlink(File.join(path, 'demo'), File.join(@root, 'linked'))
    File.chmod(0, path)
    expect { scanner.resolve(pattern: 'linked/{service}') }.to raise_error(Errno::EACCES)
  ensure
    File.chmod(0o755, path) if path
  end
end
