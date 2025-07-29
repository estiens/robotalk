# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    round
    role { 'assistant' }
    content { Faker::Lorem.sentence }
    conversation_participant { nil }
    
    trait :with_participant do
      association :conversation_participant
    end
    
    trait :error_message do
      content { 'Error occurred' }
      metadata { { 'is_error' => true, 'error' => 'API failure' } }
    end
    
    trait :streaming do
      content { '' }
      metadata { { 'status' => 'streaming' } }
    end
    
    trait :user_message do
      role { 'user' }
      content { 'User prompt or question' }
    end
    
    trait :system_message do
      role { 'system' }
      content { 'System instructions for the conversation' }
    end
    
    trait :with_metadata do
      metadata do
        {
          'model_name' => 'test-model',
          'response_metadata' => {
            'usage' => { 'prompt_tokens' => 50, 'completion_tokens' => 100 }
          },
          'response_time' => 1.5
        }
      end
    end
  end
end
