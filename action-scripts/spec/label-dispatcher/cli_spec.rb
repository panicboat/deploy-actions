require 'spec_helper'
require 'thor'

RSpec.describe 'LabelDispatcherCLI' do
  before(:all) { load File.expand_path('../../label-dispatcher/bin/dispatcher', __dir__) }

  it 'does not start commands when loaded as a library' do
    expect(LabelDispatcherCLI).not_to receive(:start)
    load File.expand_path('../../label-dispatcher/bin/dispatcher', __dir__)
  end

  {
    dispatch: [:dispatch_labels, ['123']],
    test: [:test_detection, []],
    simulate: [:simulate_github_actions, ['123']]
  }.each do |command, (action, args)|
    context "with the #{command} command" do
      let(:controller) { instance_double(Interfaces::Controllers::LabelDispatcherController) }

      before { allow(LabelDispatcherContainer).to receive(:resolve).with(:label_dispatcher_controller).and_return(controller) }

      around do |example|
        original = $stdout
        $stdout = StringIO.new
        example.run
      ensure
        $stdout = original
      end

      it 'exits 1 when the controller returns a failure Result' do
        allow(controller).to receive(action).and_return(Entities::Result.failure('boom'))
        expect { LabelDispatcherCLI.new.public_send(command, *args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      it 'does not exit when the controller returns a success Result' do
        allow(controller).to receive(action).and_return(Entities::Result.success)
        expect { LabelDispatcherCLI.new.public_send(command, *args) }.not_to raise_error
      end
    end
  end
end
