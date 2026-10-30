module Infrastructure
  class DirectoryScanner
    def initialize(repository_root:)
      @repository_root = repository_root
    end

    def resolve(pattern:, values: {})
      candidates = [{ working_directory: '', captures: {} }]
      parts = pattern.split('/')
      parts.each_index do |index|
        prefix = parts[0..index].join('/')
        candidates = candidates.flat_map do |parent|
          Dir.children(File.join(@repository_root, parent.fetch(:working_directory))).sort.filter_map do |name|
            path = [parent.fetch(:working_directory), name].reject(&:empty?).join('/')
            captures = Entities::PatternMatcher.extract(prefix, path)
            next unless captures && captures.all? { |key, value| !values.key?(key) || value == values[key] }
            next unless directory_exists?(File.join(@repository_root, path))
            { working_directory: path, captures: captures }
          end
        end
      end
      candidates.sort_by { |match| match.fetch(:working_directory) }
    end

    private

    def directory_exists?(path)
      File.stat(path).directory?
    rescue Errno::ENOENT, Errno::ENOTDIR
      # SILENT: Absent paths are valid even when entries disappear or symlinks lose their targets.
      false
    end
  end
end
