module Entities
  Service = Data.define(:id, :roots, :ignore, :stacks) do
    def self.hidden_name?(name)
      name.start_with?('.')
    end

    def initialize(**fields)
      super(**Ractor.make_shareable(fields, copy: true))
    end

    def ignored?(relative_path)
      ignore.any? do |pattern|
        # fnmatch reads a trailing ** as one segment, so "docs/**" alone would not match files nested deeper.
        glob = pattern.sub(%r{/\*\*\z}, '/**/*')
        File.fnmatch(glob, relative_path, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB)
      end
    end
  end
end
