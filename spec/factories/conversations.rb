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
    
    # Status traits
    trait :in_progress do
      status { 'in_progress' }
    end
    
    trait :complete do
      status { 'complete' }
    end
    
    trait :failed do
      status { 'failed' }
    end
    
    # Named participants trait for easier testing
    trait :with_alice_and_bob do
      after(:create) do |conversation|
        create(:conversation_participant, 
               conversation: conversation,
               name: 'Alice',
               model_id: 'openai/gpt-4o-mini',
               turn_order: 1)
        create(:conversation_participant,
               conversation: conversation,
               name: 'Bob',
               model_id: 'anthropic/claude-3-haiku',
               turn_order: 2)
        conversation.reload
      end
    end
    
    # Custom participants trait
    trait :with_custom_participants do
      transient do
        participant_configs { [] }
      end
      
      after(:create) do |conversation, evaluator|
        evaluator.participant_configs.each_with_index do |config, index|
          create(:conversation_participant,
                 conversation: conversation,
                 name: config[:name],
                 model_id: config[:model_id],
                 turn_order: index + 1,
                 system_prompt: config[:system_prompt],
                 character_prompt: config[:character_prompt])
        end
        conversation.reload
      end
    end
    
    # Trait for conversations ready to start
    trait :ready_to_start do
      with_participants
      status { 'pending' }
    end
    
    # Trait for conversation with single participant (for validation testing)
    trait :with_single_participant do
      after(:create) do |conversation|
        create(:conversation_participant,
               conversation: conversation,
               name: 'Solo',
               model_id: 'openai/gpt-4',
               turn_order: 1)
        conversation.reload
      end
    end
  end
end
