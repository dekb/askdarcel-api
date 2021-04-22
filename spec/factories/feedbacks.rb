# frozen_string_literal: true

FactoryBot.define do
  factory :feedback do
    rating { 1 }
    resource { nil }
    service { nil }
  end
end
