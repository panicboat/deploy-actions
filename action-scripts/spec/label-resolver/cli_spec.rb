require 'spec_helper'
require 'thor'

RSpec.describe 'LabelResolverCLI' do
  before(:all) do
    load File.expand_path('../../label-resolver/bin/resolver', __dir__)
  end

  it 'does not start commands when loaded as a library' do
    expect(LabelResolverCLI).not_to receive(:start)
    load File.expand_path('../../label-resolver/bin/resolver', __dir__)
  end

  [nil, '', '  '].each do |value|
    it "parses #{value.inspect} as all configured environments" do
      expect(LabelResolverCLI.new.send(:parse_environments, value)).to eq([])
    end
  end

  it 'parses comma-separated environment names' do
    expect(LabelResolverCLI.new.send(:parse_environments, ' develop,production ')).to eq(%w[develop production])
  end

  it 'passes omitted environments to the use case without reading configuration' do
    controller = instance_double(Interfaces::Controllers::LabelResolverController)
    allow(LabelResolverContainer).to receive(:resolve).with(:label_resolver_controller).and_return(controller)
    expect(controller).to receive(:resolve_from_labels).with(pr_number: 123, target_environments: [])
    LabelResolverCLI.new.resolve('123')
  end
end
