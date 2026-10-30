module UseCases
  module Shared
    class EnumerateTargets
      def initialize(directory_scanner:)
        @directory_scanner = directory_scanner
      end

      def execute(config:, services:, environments:)
        selected = services.nil? ? [nil] : services
        candidates = Entities::TargetCandidates.new
        config.stacks.each do |stack|
          stack.target_environments(environments).each do |environment|
            selected.each do |service|
              values = { 'environment' => environment }
              values['service'] = service if service
              stack.paths.each do |pattern|
                @directory_scanner.resolve(pattern: pattern, values: values, skip: Entities::Service.method(:hidden_captures?)).each do |match|
                  captures = match.fetch(:captures)
                  candidates.add(stack: stack, service: captures.fetch('service'), environment: environment, working_directory: match.fetch(:working_directory), captures: captures)
                end
              end
            end
          end
        end
        Entities::Result.success(candidates.to_a)
      end
    end
  end
end
