require 'spec_helper'

RSpec.describe Interfaces::Presenters::ConsolePresenter do
  it 'displays labels and changed files without service exclusion metadata' do
    expect do
      described_class.new.present_label_dispatch_result(deploy_labels: [Entities::DeployLabel.new('deploy:demo')], labels_added: ['deploy:demo'], labels_removed: [], changed_files: ['dystopia/demo/main.rb'])
    end.to output(/Deploy Labels: deploy:demo.*Changed Files: 1 files/m).to_stdout
  end

  it 'accepts only the dispatch result fields' do
    expect(described_class.instance_method(:present_label_dispatch_result).parameters.map(&:last)).to eq(%i[deploy_labels labels_added labels_removed changed_files])
  end
end
