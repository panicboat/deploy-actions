# Deploy label entity representing deployment target information
# Simplified to service-only labels (deploy:service)

module Entities
  class DeployLabel
    attr_reader :service

    def initialize(label_string)
      @raw_label = label_string
      parse_label!
    end

    # Get the original label string
    def label_string
      @raw_label
    end

    # Get the service name
    def service_name
      service
    end

    # Check if this is deploy:all label
    def deploy_all?
      service == 'all'
    end

    # Factory method to create deploy label from service name
    def self.from_service(service:)
      new("deploy:#{service}")
    end

    # Convert to string representation
    def to_s
      if service
        "deploy:#{service}"
      else
        @raw_label
      end
    end

    # Check if the deploy label is valid
    def valid?
      !service.nil? && service.match?(/\A[a-zA-Z0-9\-_]+\z/)
    end

    # Equality comparison
    def ==(other)
      return false unless other.is_a?(DeployLabel)
      service == other.service
    end

    # Hash for use in collections
    def hash
      [service].hash
    end

    # Enable use in sets and as hash keys
    alias eql? ==

    private

    # Parse the raw label string into components
    def parse_label!
      return unless @raw_label

      parts = @raw_label.split(':')

      return unless parts.length == 2 && parts[0] == 'deploy'

      @service = parts[1] if parts[1].match?(/\A[a-zA-Z0-9\-_]+\z/)
    end
  end
end
