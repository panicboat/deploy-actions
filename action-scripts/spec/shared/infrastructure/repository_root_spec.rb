require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Infrastructure::RepositoryRoot do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      FileUtils.mkdir_p(File.join(root, '.git'))
      example.run
    end
  end

  def directory(path)
    FileUtils.mkdir_p(File.join(@root, path))
  end

  it 'uses the source repository root' do
    expect(described_class.locate(source_path: @root, start_path: Dir.pwd)).to eq(@root)
  end

  it 'accepts git marker files' do
    FileUtils.rm_r(File.join(@root, '.git'))
    File.write(File.join(@root, '.git'), 'gitdir: elsewhere')
    expect(described_class.locate(source_path: @root, start_path: Dir.pwd)).to eq(@root)
  end

  it 'searches parent directories from the supplied start path' do
    directory('nested/deep')
    expect(described_class.locate(source_path: nil, start_path: File.join(@root, 'nested/deep'))).to eq(@root)
  end

  it 'resolves relative source paths from the supplied start path' do
    directory('nested')
    expect(described_class.locate(source_path: '..', start_path: File.join(@root, 'nested'))).to eq(@root)
  end

  it 'searches parent directories when the source path has no git marker' do
    directory('nested/deep')
    directory('unmarked')
    expect(described_class.locate(source_path: File.join(@root, 'unmarked'), start_path: File.join(@root, 'nested/deep'))).to eq(@root)
  end

  it 'fails when no repository root exists' do
    FileUtils.rm_r(File.join(@root, '.git'))
    expect { described_class.locate(source_path: nil, start_path: @root) }.to raise_error(RuntimeError, "Could not find repository root starting from #{@root}")
  end
end
