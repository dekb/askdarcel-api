# frozen_string_literal: true

# Join table between `categories` and `services`.
class ResourcesSites < ApplicationRecord
  belongs_to :resource
  belongs_to :site
end
