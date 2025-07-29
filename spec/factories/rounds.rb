# frozen_string_literal: true

FactoryBot.define do
  factory :round do
    conversation
    sequence(:number) { |n| n }
    status { 'pending' }
    next_participant_index { 0 }

    # Traits for different states
    trait :in_progress do
      status { 'in_progress' }
      started_at { Time.current }
      last_activity_at { Time.current }
    end

    trait :completed do
      in_progress # Inherit from in_progress trait
      status { 'completed' }
      completed_at { Time.current }
    end
    
    trait :failed do
      in_progress
      status { 'failed' }
      failed_at { Time.current }
      failure_reason { 'Test failure reason' }
    end

    trait :paused do
      in_progress
      status { 'paused' }
      pause_reason { 'Rate limit exceeded' }
    end

    trait :timed_out do
      in_progress
      status { 'timed_out' }
      failed_at { Time.current }
    end

    # Trait to auto-create participants
    trait :with_participants do
      transient do
        participants_count { 2 }
      end

      after(:create) do |round, evaluator|
        if evaluator.participants_count > 0
          # Create participants if they don't exist
          existing_count = round.conversation.participants.count
          needed = evaluator.participants_count - existing_count
          
          if needed > 0
            create_list(:conversation_participant, needed, 
                       conversation: round.conversation)
            round.conversation.reload
          end
        end
      end
    end
    
    # Trait for round with messages from all participants
    trait :with_all_messages do
      with_participants
      completed
      
      after(:create) do |round|
        round.conversation.participants.ordered.each do |participant|
          create(:message, round: round, conversation_participant: participant)
        end
        # Update next_participant_index to indicate all have spoken
        round.update!(next_participant_index: round.conversation.participants.count)
      end
    end
    
    # Trait for round with partial messages (some participants haven't spoken)
    trait :with_partial_messages do
      with_participants
      in_progress
      
      transient do
        messages_count { 1 }
      end
      
      after(:create) do |round, evaluator|
        participants = round.conversation.participants.ordered.take(evaluator.messages_count)
        participants.each do |participant|
          create(:message, round: round, conversation_participant: participant)
        end
        round.update!(next_participant_index: evaluator.messages_count)
      end
    end
    
    # Trait for round that's ready to resume (paused with some progress)
    trait :resumable do
      paused
      with_partial_messages
    end
  end
end