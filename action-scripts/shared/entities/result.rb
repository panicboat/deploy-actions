# Result entity for use case operation results
# Provides consistent success/failure handling across all use cases

module Entities
  class Result
    attr_reader :value, :error_message

    def initialize(success:, value: nil, error_message: nil)
      @success = success
      @value = value
      @error_message = error_message
      freeze
    end

    # Create a successful result carrying a value
    def self.success(value = nil)
      new(success: true, value: value)
    end

    # Create a failed result with an error message
    def self.failure(error_message)
      if error_message.nil? || error_message.to_s.strip.empty?
        raise ArgumentError, "error_message is required and cannot be empty"
      end
      new(success: false, error_message: error_message)
    end

    # Check if operation was successful
    def success?
      @success
    end

    # Check if operation failed
    def failure?
      !@success
    end
  end
end
