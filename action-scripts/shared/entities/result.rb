# Result entity for use case operation results
# Provides consistent success/failure handling across all use cases

module Entities
  class Result
    attr_reader :data, :error_message

    def initialize(success:, data: {}, error_message: nil)
      @success = success
      @data = data.freeze
      @error_message = error_message
      freeze
    end

    # Create a successful result with data
    def self.success(**data)
      new(success: true, data: data)
    end

    # Create a failed result with error message and optional additional data
    def self.failure(error_message:, **additional_data)
      if error_message.nil? || error_message.to_s.strip.empty?
        raise ArgumentError, "error_message is required and cannot be empty"
      end
      new(success: false, data: additional_data, error_message: error_message)
    end

    # Check if operation was successful
    def success?
      @success
    end

    # Check if operation failed
    def failure?
      !@success
    end

    # Dynamic method access to data attributes
    def method_missing(method_name, *args, &block)
      if data.key?(method_name)
        data[method_name]
      else
        nil
      end
    end

    # Check if method is available in data
    def respond_to_missing?(method_name, include_private = false)
      data.key?(method_name) || super
    end
  end
end
