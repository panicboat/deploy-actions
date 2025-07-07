# spec/shared/infrastructure/config_client_spec.rb

require 'spec_helper'

RSpec.describe Infrastructure::ConfigClient do
  subject(:config_client) { described_class.new }

  describe '#load_workflow_config' do
    context 'with valid configuration file' do
      let(:temp_config) { create_test_config(default_test_config) }

      after { temp_config.unlink }

      it 'loads and returns WorkflowConfig object' do
        config = config_client.load_workflow_config

        expect(config).to be_a(Entities::WorkflowConfig)
        expect(config.environments.keys).to include('develop', 'staging', 'production')
        expect(config.services.keys).to include('test-service', 'excluded-service')
      end

      it 'caches the loaded configuration' do
        config1 = config_client.load_workflow_config
        config2 = config_client.load_workflow_config

        expect(config1).to be(config2)
      end
    end

    context 'with non-existent configuration file' do
      before { ENV['WORKFLOW_CONFIG_PATH'] = '/non/existent/path.yaml' }

      it 'raises file not found error' do
        expect { config_client.load_workflow_config }.to raise_error(/not found/)
      end
    end

    context 'with invalid YAML' do
      let(:temp_config) { create_test_config('invalid: yaml: content: [') }

      after { temp_config.unlink }

      it 'raises YAML parsing error' do
        expect { config_client.load_workflow_config }.to raise_error(/YAML/)
      end
    end

    context 'with default configuration path' do
      before do
        ENV.delete('WORKFLOW_CONFIG_PATH')
        allow(File).to receive(:exist?).with('workflow-config.yaml').and_return(true)
        allow(File).to receive(:read).with('workflow-config.yaml').and_return(default_test_config)
      end

      it 'uses default path when environment variable not set' do
        config = config_client.load_workflow_config

        expect(config).to be_a(Entities::WorkflowConfig)
        expect(File).to have_received(:read).with('workflow-config.yaml')
      end
    end
  end

  describe '#validate_config_file' do
    context 'with valid configuration file' do
      let(:temp_config) { create_test_config(default_test_config) }

      after { temp_config.unlink }

      it 'returns success result with validation summary' do
        result = config_client.validate_config_file

        expect(result).to be_success
        expect(result.config).to be_a(Entities::WorkflowConfig)
        expect(result.validation_summary).to include('environments')
        expect(result.validation_summary).to include('services')
      end
    end

    context 'with invalid configuration' do
      let(:invalid_config) do
        <<~YAML
          environments: []
          # Missing required fields
        YAML
      end
      let(:temp_config) { create_test_config(invalid_config) }

      after { temp_config.unlink }

      it 'returns failure result with validation errors' do
        result = config_client.validate_config_file

        expect(result).to be_failure
        expect(result.validation_errors).to be_present
        expect(result.validation_errors).to include(/branch_patterns/)
      end
    end

    context 'with file not found' do
      before { ENV['WORKFLOW_CONFIG_PATH'] = '/non/existent/path.yaml' }

      it 'returns failure result with file error' do
        result = config_client.validate_config_file

        expect(result).to be_failure
        expect(result.error_message).to include('not found')
      end
    end
  end

  describe '#config_file_path' do
    context 'with environment variable set' do
      before { ENV['WORKFLOW_CONFIG_PATH'] = '/custom/path.yaml' }

      it 'returns custom path' do
        expect(config_client.send(:config_file_path)).to eq('/custom/path.yaml')
      end
    end

    context 'without environment variable' do
      before { ENV.delete('WORKFLOW_CONFIG_PATH') }

      it 'returns default path' do
        expect(config_client.send(:config_file_path)).to eq('workflow-config.yaml')
      end
    end
  end

  describe 'caching behavior' do
    let(:temp_config) { create_test_config(default_test_config) }

    after { temp_config.unlink }

    it 'caches configuration after first load' do
      allow(File).to receive(:read).and_call_original

      config1 = config_client.load_workflow_config
      config2 = config_client.load_workflow_config

      expect(File).to have_received(:read).once
      expect(config1).to be(config2)
    end

    it 'clears cache when configuration file changes' do
      original_time = Time.now - 3600
      new_time = Time.now

      allow(File).to receive(:mtime).and_return(original_time, new_time)

      config1 = config_client.load_workflow_config
      config2 = config_client.load_workflow_config

      expect(config1).not_to be(config2)
    end
  end

  describe 'error handling' do
    context 'with permission denied' do
      before do
        ENV['WORKFLOW_CONFIG_PATH'] = '/root/config.yaml'
        allow(File).to receive(:exist?).with('/root/config.yaml').and_return(true)
        allow(File).to receive(:read).with('/root/config.yaml').and_raise(Errno::EACCES)
      end

      it 'raises permission error with helpful message' do
        expect { config_client.load_workflow_config }.to raise_error(/permission/i)
      end
    end

    context 'with malformed YAML' do
      let(:temp_config) { create_test_config("invalid:\n  - yaml\n  content") }

      after { temp_config.unlink }

      it 'raises YAML error with line information' do
        expect { config_client.load_workflow_config }.to raise_error(/YAML.*line/i)
      end
    end
  end
end