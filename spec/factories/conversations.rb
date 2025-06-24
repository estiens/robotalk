FactoryBot.define do
  factory :conversation do
    association :user
    conversation_topic { "Test Topic" }
    dialogue_instructions { "Test dialogue instructions." }
    max_rounds { 5 }
  end
end
