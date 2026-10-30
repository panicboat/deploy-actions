module Entities
  ListedTarget = Data.define(:target, :excluded, :root) do
    alias_method :excluded?, :excluded
  end
end
