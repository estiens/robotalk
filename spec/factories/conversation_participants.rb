# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_participant do
    conversation
    name { 'Test Participant' }
    model_id { 'openai/gpt-4o-mini' }
    sequence(:turn_order) { |n| n }
    
    # Named participant traits
    trait :alice do
      name { 'Alice' }
      model_id { 'openai/gpt-4o-mini' }
      turn_order { 1 }
    end
    
    trait :bob do
      name { 'Bob' }
      model_id { 'anthropic/claude-3-haiku' }
      turn_order { 2 }
    end
    
    trait :with_system_prompt do
      system_prompt { 'You are a helpful AI assistant.' }
    end
    
    trait :with_character_prompt do
      character_prompt { 'Be friendly and conversational.' }
    end
    
    trait :with_full_prompts do
      with_system_prompt
      with_character_prompt
    end
  end
end
