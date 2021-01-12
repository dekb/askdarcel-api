# frozen_string_literal: true

# Join table between `categories` and `services`.
class CategoriesSites < ApplicationRecord
  belongs_to :category
  belongs_to :site
end
