# frozen_string_literal: true

class Site < ActiveRecord::Base
  has_and_belongs_to_many(:categories,
                          join_table: "categories_sites",
                          foreign_key: "site_id")
  has_and_belongs_to_many(:resources,
                          join_table: "resources_sites",
                          foreign_key: "site_id")
end
