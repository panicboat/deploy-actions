module Entities
  Service = Data.define(:id, :roots, :ignore, :stacks) do
    def self.name_format
      '[a-zA-Z0-9_-]+'
    end

    def self.valid_name?(name)
      /\A#{name_format}\z/.match?(name)
    end

    def self.invalid_name_message(name)
      "Invalid service name: #{name.inspect} (use a name matching #{name_format})"
    end

    def self.captures_invalid_name?(captures)
      captures.key?('service') && !valid_name?(captures['service'])
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
