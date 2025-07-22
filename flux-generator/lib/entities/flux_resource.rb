require 'dry-struct'


module Entities
  class FluxResource < Dry::Struct
    attribute :api_version, Types::String
    attribute :kind, Types::String
    attribute :metadata, Types::Hash
    attribute :spec, Types::Hash

    def to_yaml
      result = {
        'apiVersion' => api_version,
        'kind' => kind
      }

      # Add metadata only if not empty
      result['metadata'] = metadata unless metadata.empty?

      # For kustomize.config.k8s.io, resources is at root level
      # For kustomize.toolkit.fluxcd.io, everything is under spec
      if api_version == 'kustomize.config.k8s.io/v1beta1'
        result.merge!(spec)
      else
        result['spec'] = spec
      end

      result.to_yaml
    end

    def self.git_repository(name:, namespace:, url:, branch: 'main', interval: '1m0s')
      new(
        api_version: 'source.toolkit.fluxcd.io/v1',
        kind: 'GitRepository',
        metadata: {
          'name' => name,
          'namespace' => namespace
        },
        spec: {
          'interval' => interval,
          'ref' => { 'branch' => branch },
          'url' => url
        }
      )
    end

    def self.kustomization(name:, namespace:, path:, source_ref:, interval: '10m0s',
                         prune: true, target_namespace: nil, post_build: nil)
      spec = {
        'interval' => interval,
        'path' => path,
        'prune' => prune,
        'sourceRef' => source_ref
      }
      spec['targetNamespace'] = target_namespace if target_namespace
      spec['postBuild'] = post_build if post_build

      new(
        api_version: 'kustomize.toolkit.fluxcd.io/v1',
        kind: 'Kustomization',
        metadata: {
          'name' => name,
          'namespace' => namespace
        },
        spec: spec
      )
    end

    def self.kustomize_config(resources:)
      new(
        api_version: 'kustomize.config.k8s.io/v1beta1',
        kind: 'Kustomization',
        metadata: {},
        spec: { 'resources' => resources }
      )
    end
  end
end
