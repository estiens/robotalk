FactoryBot.define do
  factory :conversation_participant do
    association :conversation
    name { "Test Participant" }
    model_id { "openai/gpt-4o-mini" }
    sequence(:turn_order)
  end
end
