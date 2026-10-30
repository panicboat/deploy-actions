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
    expect(controller).to receive(:resolve_from_labels).with(pr_number: 123, target_environments: []).and_return(Entities::Result.success)
    LabelResolverCLI.new.resolve('123')
  end

  {
    resolve: :resolve_from_labels,
    test: :test_deployment_workflow,
    simulate: :simulate_github_actions,
    debug: :debug_deployment_workflow
  }.each do |command, action|
    context "with the #{command} command" do
      let(:controller) { instance_double(Interfaces::Controllers::LabelResolverController) }

      before { allow(LabelResolverContainer).to receive(:resolve).with(:label_resolver_controller).and_return(controller) }

      around do |example|
        original = $stdout
        $stdout = StringIO.new
        example.run
      ensure
        $stdout = original
      end

      it 'exits 1 when the controller returns a failure Result' do
        allow(controller).to receive(action).and_return(Entities::Result.failure('boom'))
        expect { LabelResolverCLI.new.public_send(command, '123') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it 'does not exit when the controller returns a success Result' do
        allow(controller).to receive(action).and_return(Entities::Result.success)
        expect { LabelResolverCLI.new.public_send(command, '123') }.not_to raise_error
      end
    end
  end
end
