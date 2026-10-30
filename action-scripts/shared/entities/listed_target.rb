module Entities
  ListedTarget = Data.define(:target, :excluded) do
    alias_method :excluded?, :excluded
  end
end
