require 'open3'

module Infrastructure
  class GitClient
    def initialize(repository_root:)
      @repository_root = repository_root
    end

    def changed_files(base_ref:, head_ref:)
      if base_ref && head_ref
        diff("#{base_ref}...#{head_ref}")
      elsif base_ref
        diff(base_ref)
      else
        (diff('--cached') + diff).uniq
      end
    end

    private

    def diff(*args)
      output, error, status = Open3.capture3('git', '-C', @repository_root, 'diff', '--name-only', *args)
      raise "git diff failed: #{error.strip}" unless status.success?
      output.split("\n").reject(&:empty?)
    end
  end
end
