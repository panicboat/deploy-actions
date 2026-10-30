module Entities
  class Result
    attr_reader :value, :error_message

    def initialize(success:, value: nil, error_message: nil)
      @success = success
      @value = value
      @error_message = error_message
      freeze
    end

    def self.success(value = nil)
      new(success: true, value: value)
    end

    def self.failure(error_message)
      if error_message.nil? || error_message.to_s.strip.empty?
        raise ArgumentError, "error_message is required and cannot be empty"
      end
      new(success: false, error_message: error_message)
    end

    def success?
      @success
    end

    def failure?
      !@success
    end
  end
end
