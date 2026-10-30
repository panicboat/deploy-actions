module Entities
  class ChangeDetector
    def initialize(config)
      @config = config
    end

    def services(changed_files)
      candidates = TargetCandidates.new
      shared = changed_files.flat_map { |file| shared_services(file, candidates) }
      (shared + candidates.to_a.reject(&:excluded?).map(&:service)).uniq
    end

    private

    def shared_services(file, candidates)
      @config.services.flat_map do |service|
        service.roots.each_with_index.filter_map do |root, root_index|
          name = service_name(service, root, file)
          next unless name
          in_stack = service.stacks.map { |stack| add_candidates(candidates, stack, stack.paths[root_index], name, file) }.any?
          name unless in_stack
        end
      end
    end

    def service_name(service, root, file)
      captures = PatternMatcher.extract_prefix(root, file)
      return unless captures
      name = captures.fetch('service')
      return unless Service.valid_name?(name)
      relative_path = file.delete_prefix("#{PatternMatcher.expand(root, captures)}/")
      name unless service.ignored?(relative_path)
    end

    def add_candidates(candidates, stack, pattern, service, file)
      captures = PatternMatcher.extract_prefix(pattern, file)
      return false unless captures
      environments = stack.target_environments(captures.key?('environment') ? [captures['environment']] : stack.declared_environment_names)
      return false if environments.empty?
      directory = PatternMatcher.expand(pattern, captures)
      environments.each do |environment|
        candidates.add(stack: stack, service: service, environment: environment, working_directory: directory, captures: captures)
      end
      # A dot path holds every file under the root, so counting it would stop shared-file detection for the other stacks.
      !stack.path.empty?
    end
  end
end
