module Infrastructure
  module RepositoryRoot
    def self.locate(source_path:, start_path:)
      if source_path && !source_path.empty?
        root = File.expand_path(source_path, start_path)
        return root if File.directory?(root) && git_marker?(root)
      end

      # FALLBACK: Local runs may retain SOURCE_REPO_PATH after the source checkout becomes unavailable.
      current = File.expand_path(start_path)
      loop do
        return current if git_marker?(current)
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
      raise "Could not find repository root starting from #{start_path}"
    end

    def self.git_marker?(path)
      git_path = File.join(path, '.git')
      File.directory?(git_path) || File.file?(git_path)
    end
    private_class_method :git_marker?
  end
end
