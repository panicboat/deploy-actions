require 'fileutils'


module Repositories
  class FileSystemRepository
    def ensure_directory(path)
      FileUtils.mkdir_p(path) unless Dir.exist?(path)
      puts "📦 Created directory: #{path}"
    end

    def write_file(path, content)
      ensure_directory(File.dirname(path))
      File.write(path, content)
      puts "📝 Generated file: #{path}"
    end

    def directory_exists?(path)
      Dir.exist?(path)
    end

    def find_yaml_files(directory)
      return [] unless directory_exists?(directory)

      Dir.glob("#{directory}/**/*.yaml").sort
    end

    def relative_path(file_path, base_path)
      Pathname.new(file_path).relative_path_from(Pathname.new(base_path)).to_s
    end
  end
end
