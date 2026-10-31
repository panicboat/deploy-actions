require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe UseCases::LabelResolver::ListServiceTargets do
  let(:stack_config) do
    Entities::WorkflowConfigParser.parse('services' => [{ 'id' => 'app', 'roots' => ['{service}'], 'stacks' => [
      { 'id' => 'aws', 'path' => 'aws' },
      { 'id' => 'alb', 'path' => 'alb', 'exclude' => [{ 'service' => 'demo' }] }
    ] }])
  end
  let(:included) { Entities::TargetCandidate.new(stack: stack_config.stacks[0], service: 'demo', environment: nil, working_directory: 'demo/aws', captures: {}) }
  let(:excluded) { Entities::TargetCandidate.new(stack: stack_config.stacks[1], service: 'demo', environment: nil, working_directory: 'demo/alb', captures: {}) }
  let(:unbuildable_stack) { Entities::Stack.new(id: 'aws', path: 'aws', paths: ['{service}/aws'], attributes: { 'repository' => 'ghcr.io/{team}/{service}' }, environments: nil, exclude: [{ 'service' => 'demo' }]) }
  let(:unbuildable) { Entities::TargetCandidate.new(stack: unbuildable_stack, service: 'demo', environment: nil, working_directory: 'demo/aws', captures: {}) }

  context 'with a stubbed candidate list' do
    let(:list_candidates) { instance_double(UseCases::Shared::ListCandidates) }
    subject(:use_case) { described_class.new(list_candidates: list_candidates) }

    it 'lists the service with the requested environments' do
      allow(list_candidates).to receive(:execute).with(services: ['demo'], environments: ['develop']).and_return(Entities::Result.success([included, excluded]))

      result = use_case.execute(service: 'demo', environments: ['develop'])

      expect(result).to be_success
      expect(list_candidates).to have_received(:execute).with(services: ['demo'], environments: ['develop'])
    end

    it 'carries the targets that are not excluded' do
      allow(list_candidates).to receive(:execute).and_return(Entities::Result.success([included, excluded]))

      expect(use_case.execute(service: 'demo', environments: []).value).to eq([included.to_deployment_target])
    end

    it 'carries no targets when every candidate is excluded' do
      allow(list_candidates).to receive(:execute).and_return(Entities::Result.success([excluded]))

      expect(use_case.execute(service: 'demo', environments: []).value).to eq([])
    end

    it 'looks up all as a service named all' do
      allow(list_candidates).to receive(:execute).and_return(Entities::Result.success([]))

      result = use_case.execute(service: 'all', environments: [])

      expect(result).to be_success
      expect(list_candidates).to have_received(:execute).with(services: ['all'], environments: [])
    end

    ['demo/aws', 'a.b', '.hidden', "demo\n"].each do |name|
      it "rejects the service name #{name.inspect} before listing candidates" do
        allow(list_candidates).to receive(:execute)

        result = use_case.execute(service: name, environments: [])

        expect(result).to be_failure
        expect(result.error_message).to eq("Invalid service name: #{name.inspect} (use a name matching [a-zA-Z0-9_-]+)")
        expect(list_candidates).not_to have_received(:execute)
      end
    end

    it 'returns the failure of the candidate list as it is' do
      allow(list_candidates).to receive(:execute).and_return(Entities::Result.failure('Target environments not found in configuration: preview'))

      result = use_case.execute(service: 'demo', environments: ['preview'])

      expect(result).to be_failure
      expect(result.error_message).to eq('Target environments not found in configuration: preview')
    end

    it 'reports an enumeration error as a failure' do
      allow(list_candidates).to receive(:execute).and_raise(RuntimeError, "Conflicting captures for stack 'aws' at 'demo/aws'")

      result = use_case.execute(service: 'demo', environments: [])

      expect(result).to be_failure
      expect(result.error_message).to eq("Failed to resolve service targets: Conflicting captures for stack 'aws' at 'demo/aws'")
    end

    it 'reports a candidate that cannot be built as a failure instead of raising' do
      allow(list_candidates).to receive(:execute).and_return(Entities::Result.success([included, unbuildable]))

      result = nil
      expect { result = use_case.execute(service: 'demo', environments: []) }.not_to raise_error

      expect(result).to be_failure
      expect(result.error_message).to match(/\AFailed to resolve service targets: .*\{team\}/)
    end
  end

  context 'with the directories of a repository' do
    let(:config_hash) do
      { 'services' => [{ 'id' => 'app', 'roots' => ['apps/{service}'], 'stacks' => [
        { 'id' => 'container', 'path' => '.' },
        { 'id' => 'kustomize', 'path' => 'overlays/{environment}' },
        { 'id' => 'alb', 'path' => 'alb', 'exclude' => [{ 'service' => 'demo' }] }
      ] }] }
    end
    let(:config_client) { instance_double(Infrastructure::ConfigClient, load_workflow_config: Entities::WorkflowConfigParser.parse(config_hash)) }
    let(:directory_scanner) { Infrastructure::DirectoryScanner.new(repository_root: @root) }
    subject(:use_case) do
      described_class.new(
        list_candidates: UseCases::Shared::ListCandidates.new(
          config_client: config_client,
          resolve_environments: UseCases::Shared::ResolveEnvironments.new(directory_scanner: directory_scanner),
          enumerate_targets: UseCases::Shared::EnumerateTargets.new(directory_scanner: directory_scanner)
        )
      )
    end

    around do |example|
      Dir.mktmpdir do |root|
        @root = root
        %w[apps/demo/overlays/develop apps/demo/alb apps/api].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
        example.run
      end
    end

    it 'lists the targets of a service apart from the excluded candidates' do
      value = use_case.execute(service: 'demo', environments: ['develop']).value

      expect(value.map(&:to_matrix_item)).to eq([
        { service: 'demo', environment: nil, stack: 'container', working_directory: 'apps/demo' },
        { service: 'demo', environment: 'develop', stack: 'kustomize', working_directory: 'apps/demo/overlays/develop' }
      ])
    end

    it 'lists nothing for all when no directory is named all' do
      result = use_case.execute(service: 'all', environments: [])

      expect(result).to be_success
      expect(result.value).to eq([])
    end

    it 'lists only the directory named all for all' do
      FileUtils.mkdir_p(File.join(@root, 'apps/all'))

      expect(use_case.execute(service: 'all', environments: []).value.map(&:to_matrix_item)).to eq([
        { service: 'all', environment: nil, stack: 'container', working_directory: 'apps/all' }
      ])
    end

    it 'lists nothing for an unknown service' do
      result = use_case.execute(service: 'missing', environments: [])

      expect(result).to be_success
      expect(result.value).to eq([])
    end

    it 'fails for an environment outside the union of declared and discovered environments' do
      result = use_case.execute(service: 'demo', environments: ['preview'])

      expect(result).to be_failure
      expect(result.error_message).to eq('Target environments not found in configuration: preview')
    end
  end
end
