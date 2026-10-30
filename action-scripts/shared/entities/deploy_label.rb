# Deploy label entity representing deployment target information
# Service-only labels in the form <prefix><service>

module Entities
  class DeployLabel
    DEFAULT_PREFIX = 'deploy:'.freeze

    attr_reader :service, :prefix

    def initialize(raw_label, prefixes: [DEFAULT_PREFIX])
      @raw_label = raw_label
      @prefixes = prefixes
      parse_label!
    end

    # Factory method to create deploy label from service name
    def self.from_service(service:, prefix: DEFAULT_PREFIX)
      new("#{prefix}#{service}", prefixes: [prefix])
    end

    # Convert to string representation
    def to_s
      if service
        "#{prefix}#{service}"
      else
        @raw_label
      end
    end

    # Check if the deploy label is valid
    def valid?
      Service.valid_name?(service)
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

      @prefix = @prefixes.find do |prefix|
        @raw_label.start_with?(prefix) && Service.valid_name?(@raw_label.delete_prefix(prefix))
      end
      @service = @raw_label.delete_prefix(@prefix) if @prefix
    end
  end
end
