require 'spec_helper'

RSpec.describe Infrastructure::GitHubClient do
  let(:octokit) { instance_double(Octokit::Client) }
  let(:labels) { %w[release/api manual/web enhancement].map { |name| double(name: name) } }
  subject(:client) { described_class.new(token: 'token', repository: 'owner/repo') }

  before do
    allow(Octokit::Client).to receive(:new).and_return(octokit)
    allow(octokit).to receive(:labels_for_issue).with('owner/repo', 1).and_return(labels)
  end

  it 'returns labels starting with the given prefix' do
    expect(client.get_deploy_labels(1, prefix: 'release/')).to eq(['release/api'])
  end

  it 'returns every label name in PR information' do
    pr = double(head: double(ref: 'feature', sha: 'head'), base: double(ref: 'main', sha: 'base'), title: 'title', state: 'open', merged: false, number: 1, html_url: 'url')
    allow(octokit).to receive(:pull_request).with('owner/repo', 1).and_return(pr)
    expect(client.get_pr_info(1)[:labels]).to eq(%w[release/api manual/web enhancement])
  end

  it 'lets the caller prefix errors from reading PR information' do
    allow(octokit).to receive(:pull_request).and_raise(Octokit::NotFound)
    expect { client.get_pr_info(1) }.to raise_error(Octokit::NotFound)
  end

  %w[production-api release/production deploy:api].each do |name|
    it "creates #{name} with color 0052cc" do
      allow(octokit).to receive(:label).and_raise(Octokit::NotFound)
      allow(octokit).to receive(:add_label)
      client.ensure_label_exists(name)
      expect(octokit).to have_received(:add_label).with('owner/repo', name, '0052cc', description: 'Auto-generated deployment label')
    end
  end
end
