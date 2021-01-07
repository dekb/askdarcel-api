# frozen_string_literal: true

class Feedback < ApplicationRecord
  validates :rating, inclusion: { in: %w(upvote downvote) }
  belongs_to :resource
  belongs_to :service
  has_one :review, dependent: :destroy
  accepts_nested_attributes_for :review, reject_if: proc { |attributes| attributes['review'].blank? && attributes['tags'].blank? }
end
