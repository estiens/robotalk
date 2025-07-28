# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    conversation
    role { 'user' }
    content { Faker::Lorem.sentence }
    conversation_participant factory: %i[conversation_participant]
  end
end
