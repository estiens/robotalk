FactoryBot.define do
  factory :message do
    association :conversation
    role { "user" }
    content { Faker::Lorem.sentence }
    association :conversation_participant, factory: :conversation_participant
  end
end
