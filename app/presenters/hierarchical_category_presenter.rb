# frozen_string_literal: true

class HierarchicalCategoryPresenter < Jsonite
  property :name
  property :id
  property :top_level
  property :featured
  property :children, with: CategoryPresenter
end
