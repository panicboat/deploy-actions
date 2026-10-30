require 'spec_helper'

RSpec.describe Interfaces::Controllers::ConfigManagerController do
  let(:validate_config) { instance_double(UseCases::ConfigManagement::ValidateConfig) }
  let(:test_service) { instance_double(UseCases::ConfigManagement::TestService) }
  let(:presenter) { instance_double(Interfaces::Presenters::ConsolePresenter, present_config_validation_result: nil, present_service_test_result: nil, present_error: nil) }

  subject(:controller) { described_class.new(validate_config: validate_config, test_service: test_service, presenter: presenter) }

  describe '#validate' do
    it 'presents the summary of a valid configuration and returns the success Result' do
      validation = UseCases::ConfigManagement::Validation.new(config: build(:workflow_config), summary: 'Configuration validation successful')
      allow(validate_config).to receive(:execute).and_return(Entities::Result.success(validation))

      result = controller.validate

      expect(result).to be_success
      expect(result.value).to eq(validation)
      expect(presenter).to have_received(:present_config_validation_result).with(valid: true, config: validation.config, summary: 'Configuration validation successful')
    end

    it 'presents the errors of an invalid configuration and returns the failure Result' do
      allow(validate_config).to receive(:execute).and_return(Entities::Result.failure('services[0].roots is empty'))

      result = controller.validate

      expect(result).to be_failure
      expect(result.error_message).to eq('services[0].roots is empty')
      expect(presenter).to have_received(:present_config_validation_result).with(valid: false, errors: ['services[0].roots is empty'])
    end
  end

  describe '#test_service' do
    let(:candidates) { [instance_double(Entities::TargetCandidate)] }

    it 'presents the candidates for the service and environment' do
      allow(test_service).to receive(:execute).with(service_name: 'demo', environment: 'production').and_return(Entities::Result.success(candidates))

      result = controller.test_service(service_name: 'demo', environment: 'production')

      expect(result.value).to eq(candidates)
      expect(presenter).to have_received(:present_service_test_result).with(service_name: 'demo', candidates: candidates)
    end

    it 'presents the failure without presenting partial candidates' do
      allow(test_service).to receive(:execute).and_return(Entities::Result.failure('Target environments not found in configuration: qa'))

      result = controller.test_service(service_name: 'demo', environment: 'qa')

      expect(result).to be_failure
      expect(presenter).to have_received(:present_error).with('Target environments not found in configuration: qa')
      expect(presenter).not_to have_received(:present_service_test_result)
    end
  end
end
