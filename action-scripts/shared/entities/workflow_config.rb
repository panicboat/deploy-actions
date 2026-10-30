module Entities
  WorkflowConfig = Data.define(:label_prefix, :extra_label_prefixes, :services) do
    def initialize(**fields)
      super(**Ractor.make_shareable(fields, copy: true))
    end

    def stacks
      services.flat_map(&:stacks)
    end

    def label_prefixes
      [label_prefix] + extra_label_prefixes
    end

    def declared_environment_names
      stacks.flat_map(&:declared_environment_names).uniq
    end
  end
end
