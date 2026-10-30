require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec.describe Infrastructure::GitClient do
  subject(:client) { described_class.new(repository_root: @root) }

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      git('init', '--quiet')
      write('a.txt', 'a')
      commit('first')
      @first = git('rev-parse', 'HEAD').strip
      write('b.txt', 'b')
      commit('second')
      @second = git('rev-parse', 'HEAD').strip
      example.run
    end
  end

  def git(*args)
    output, error, status = Open3.capture3({ 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' }, 'git', '-C', @root, '-c', 'user.name=spec', '-c', 'user.email=spec@example.com', '-c', 'commit.gpgsign=false', *args)
    raise error unless status.success?
    output
  end

  def write(path, content)
    File.write(File.join(@root, path), content)
  end

  def commit(message)
    git('add', '--all')
    git('commit', '--quiet', '-m', message)
  end

  it 'returns files changed between two refs' do
    expect(client.changed_files(base_ref: @first, head_ref: @second)).to eq(['b.txt'])
  end

  it 'returns files changed since the base ref when no head ref is given' do
    write('a.txt', 'changed')
    expect(client.changed_files(base_ref: @first, head_ref: nil)).to eq(['a.txt', 'b.txt'])
  end

  it 'returns the union of staged and unstaged changes without duplicates when no refs are given' do
    write('b.txt', 'staged')
    write('c.txt', 'c')
    git('add', 'b.txt', 'c.txt')
    write('b.txt', 'unstaged')
    write('a.txt', 'unstaged')
    expect(client.changed_files(base_ref: nil, head_ref: nil)).to eq(['b.txt', 'c.txt', 'a.txt'])
  end

  it 'raises instead of falling back when a ref does not exist' do
    write('a.txt', 'changed')
    expect { client.changed_files(base_ref: 'missing', head_ref: @second) }.to raise_error(RuntimeError, /git diff failed: .*missing/m)
    expect { client.changed_files(base_ref: 'missing', head_ref: nil) }.to raise_error(RuntimeError, /git diff failed/)
  end

  it 'reads a ref that names an existing file as a ref, not as a path' do
    write('a.txt', 'changed')
    expect { client.changed_files(base_ref: 'a.txt', head_ref: nil) }.to raise_error(RuntimeError, /git diff failed/)
  end

  it 'reads a ref that starts with a dash as a ref, not as an option' do
    output_path = File.join(@root, 'diff-output')
    expect { client.changed_files(base_ref: "--output=#{output_path}", head_ref: nil) }.to raise_error(RuntimeError, /git diff failed/)
    expect { client.changed_files(base_ref: "--output=#{output_path}", head_ref: @second) }.to raise_error(RuntimeError, /git diff failed/)
    expect(Dir.glob("#{output_path}*")).to be_empty
  end

  it 'raises when a head ref is given without a base ref' do
    write('a.txt', 'changed')
    expect { client.changed_files(base_ref: nil, head_ref: @second) }.to raise_error(ArgumentError, 'head_ref requires base_ref')
  end
end
