require 'dry-struct'


module Entities
  class ManifestFile < Dry::Struct
    attribute :path, Types::String
    attribute :relative_path, Types::String
    attribute :service_name, Types::String
    attribute :directory, Types::String

    def self.from_path(full_path, environment_path)
      relative_path = full_path.gsub(/^#{Regexp.escape(environment_path)}\//, '')
      service_name = File.basename(full_path, '.yaml')
      directory = File.dirname(relative_path)

      new(
        path: full_path,
        relative_path: relative_path,
        service_name: service_name,
        directory: directory
      )
    end

    def in_subdirectory?
      directory != '.'
    end

    def resource_name
      return service_name unless in_subdirectory?

      relative_path.gsub('/', '-').gsub(/\.yaml$/, '')
    end

    def target_path
      return service_name unless in_subdirectory?

      directory
    end
  end
end
