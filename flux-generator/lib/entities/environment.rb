require 'dry-struct'

module Types
  include Dry.Types()
end

module Entities
  class Environment < Dry::Struct
    attribute :name, Types::String
    attribute :path, Types::String
    attribute :cluster_path, Types::String

    def self.from_name(name)
      new(
        name: name,
        path: "./#{name}",
        cluster_path: "./clusters/#{name}"
      )
    end

    def flux_system_path
      "#{cluster_path}/flux-system"
    end

    def apps_path
      "#{cluster_path}/apps"
    end

    def valid?
      !name.empty?
    end
  end
end
