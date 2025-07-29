# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    user
    conversation_topic { 'Test Topic' }
    dialogue_instructions { 'Test dialogue instructions.' }
    max_rounds { 5 }

    # Trait for conversations with participants
    trait :with_participants do
      transient do
        participants_count { 2 }
      end

      after(:create) do |conversation, evaluator|
        create_list(:conversation_participant, evaluator.participants_count, 
                   conversation: conversation)
        conversation.reload
      end
    end
    
    # State traits - these create the conversation with appropriate rounds
    trait :with_current_round do
      with_participants
      
      after(:create) do |conversation|
        create(:round, :in_progress, conversation: conversation)
      end
    end
    
    trait :with_completed_round do
      with_participants
      
      after(:create) do |conversation|
        create(:round, :completed, conversation: conversation)
      end
    end
    
    trait :with_failed_round do
      with_participants
      
      after(:create) do |conversation|
        create(:round, :failed, conversation: conversation)
      end
    end
    
    trait :with_multiple_rounds do
      with_participants
      
      transient do
        rounds_count { 3 }
      end
      
      after(:create) do |conversation, evaluator|
        evaluator.rounds_count.times do |i|
          status = i == evaluator.rounds_count - 1 ? :in_progress : :completed
          create(:round, status, conversation: conversation, number: i + 1)
        end
      end
    end
  end
end
