require 'spec_helper'

RSpec.describe Entities::Service do
  def service(ignore)
    described_class.new(id: 'app', roots: ['apps/{service}'], ignore: ignore, stacks: [])
  end

  it 'freezes its collections' do
    built = described_class.new(id: 'app', roots: ['apps/{service}'], ignore: ['docs/**'], stacks: [])
    expect(built).to be_frozen
    expect(built.roots).to be_frozen
    expect(built.ignore).to be_frozen
    expect(built.ignore.first).to be_frozen
    expect(built.stacks).to be_frozen
  end

  it 'does not freeze the given collections' do
    ignore = ['docs/**']
    service(ignore)
    expect(ignore).not_to be_frozen
  end

  describe '#ignored?' do
    it 'matches nothing without ignore patterns' do
      expect(service([]).ignored?('README.md')).to be(false)
    end

    it 'matches zero or more directories with **/' do
      expect(service(['**/README.md']).ignored?('README.md')).to be(true)
      expect(service(['**/README.md']).ignored?('aws/modules/README.md')).to be(true)
    end

    it 'does not let * cross directories' do
      expect(service(['*.md']).ignored?('NOTES.md')).to be(true)
      expect(service(['*.md']).ignored?('aws/NOTES.md')).to be(false)
    end

    it 'matches every file below a directory with a trailing /**' do
      expect(service(['docs/**']).ignored?('docs/a.md')).to be(true)
      expect(service(['docs/**']).ignored?('docs/a/b.md')).to be(true)
      expect(service(['docs/**']).ignored?('aws/docs/a.md')).to be(false)
    end

    it 'matches files starting with a dot' do
      expect(service(['*']).ignored?('.terraform-version')).to be(true)
      expect(service(['**/*.md']).ignored?('.github/a.md')).to be(true)
    end

    it 'matches when any pattern matches' do
      expect(service(['*.txt', '**/*.md']).ignored?('aws/a.md')).to be(true)
      expect(service(['*.txt', '**/*.md']).ignored?('aws/main.tf')).to be(false)
    end
  end

  describe '.hidden_name?' do
    it 'treats a name starting with a dot as hidden' do
      expect(described_class.hidden_name?('.preview')).to be(true)
      expect(described_class.hidden_name?('.')).to be(true)
    end

    it 'treats other names as visible' do
      expect(described_class.hidden_name?('demo')).to be(false)
      expect(described_class.hidden_name?('demo.v2')).to be(false)
    end
  end

  describe '.hidden_captures?' do
    it 'treats captures with a hidden service as hidden' do
      expect(described_class.hidden_captures?('team' => 'platform', 'service' => '.hidden')).to be(true)
    end

    it 'treats captures with a visible service as visible' do
      expect(described_class.hidden_captures?('team' => '.platform', 'service' => 'demo')).to be(false)
    end

    it 'treats captures without a service as visible' do
      expect(described_class.hidden_captures?('team' => '.platform')).to be(false)
    end
  end
end
