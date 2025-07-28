# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AssistantMessage STI Edge Cases' do
  let(:conversation) { create('conversation', max_rounds: 3) }
  let(:participant1) { create('conversation_participant', conversation: conversation, turn_order: 1) }
  let(:participant2) { create('conversation_participant', conversation: conversation, turn_order: 2) }

  describe 'Message type promotion flow' do
    it 'correctly handles the full streaming to finalized message flow' do
      # Step 1: acts_as_chat creates an empty shell
      shell_message = Message.create!(
        conversation: conversation,
        role: 'assistant',
        content: '',
        round_number: 1
      )

      expect(shell_message.type).to be_nil
      expect(shell_message).to be_a(Message)
      expect(shell_message).not_to be_a(AssistantMessage)

      # Step 2: During streaming, content is updated incrementally
      shell_message.update!(content: 'Hello, ')
      shell_message.update!(content: 'Hello, world!')

      # Message is still a base Message, not AssistantMessage
      expect(Message.find(shell_message.id).type).to be_nil

      # Step 3: persist_message_completion promotes to AssistantMessage
      shell_message.update_columns(
        type: 'AssistantMessage',
        conversation_participant_id: participant1.id,
        input_tokens: 10,
        output_tokens: 20
      )

      # Step 4: Reload as AssistantMessage
      assistant_message = AssistantMessage.find(shell_message.id)

      expect(assistant_message).to be_a(AssistantMessage)
      expect(assistant_message.conversation_participant).to eq(participant1)
      expect(assistant_message.input_tokens).to eq(10)
      expect(assistant_message.output_tokens).to eq(20)
    end
  end

  describe 'Concurrent message creation' do
    it 'handles multiple participants creating messages simultaneously' do
      # Simulate concurrent message creation
      message1 = nil
      message2 = nil

      thread1 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          message1 = AssistantMessage.create!(
            conversation: conversation.reload,
            conversation_participant: participant1,
            role: 'assistant',
            content: 'Participant 1 message',
            round_number: 1
          )
        end
      end

      thread2 = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          message2 = AssistantMessage.create!(
            conversation: conversation.reload,
            conversation_participant: participant2,
            role: 'assistant',
            content: 'Participant 2 message',
            round_number: 1
          )
        end
      end

      thread1.join
      thread2.join

      conversation.reload

      # Both messages should exist
      expect(message1).to be_persisted
      expect(message2).to be_persisted

      # Round should advance only once
      expect(conversation.current_round).to eq(2)

      # Both messages should have the same round number
      expect(message1.round_number).to eq(1)
      expect(message2.round_number).to eq(1)
    end
  end

  describe 'Failed streaming scenarios' do
    it 'handles messages that fail during streaming' do
      # Create a shell that simulates a failed stream
      failed_shell = Message.create!(
        conversation: conversation,
        role: 'assistant',
        content: '',
        metadata: { status: 'streaming', error: 'Connection lost' }
      )

      # Message remains as base Message type
      expect(failed_shell.type).to be_nil

      # Should not be counted as a finalized assistant message
      expect(conversation.assistant_messages.count).to eq(0)

      # Should not affect round progression
      expect(conversation.current_round).to eq(1)
    end

    it 'handles partial participant assignment failure' do
      # Create message without participant (simulating assignment failure)
      orphan_message = AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: nil,
        role: 'assistant',
        content: 'Orphaned message',
        round_number: 1
      )

      expect(orphan_message).to be_persisted
      expect(orphan_message.conversation_participant).to be_nil

      # Should still trigger round logic but may cause issues
      # This is a known edge case that needs handling
    end
  end

  describe 'Round number edge cases' do
    before do
      # Force creation of participants
      participant1
      participant2
      # Ensure we have exactly 2 participants for these tests
      expect(conversation.participants.count).to eq(2)
    end

    it "automatically sets round_number from conversation's current_round" do
      conversation.update!(current_round: 3)

      message = AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant1,
        role: 'assistant',
        content: 'Auto round number'
      )

      # The before_create callback should set round_number
      expect(message.round_number).to eq(3)
    end

    it 'handles messages with explicitly set round_number' do
      message = AssistantMessage.new(
        conversation: conversation,
        conversation_participant: participant1,
        role: 'assistant',
        content: 'Explicit round',
        round_number: 5
      )

      message.save!

      # Should keep the explicitly set round_number
      expect(message.round_number).to eq(5)
    end

    it 'shows round advancement logic behavior with incomplete rounds' do
      # Start with current_round = 1
      expect(conversation.current_round).to eq(1)
      expect(conversation.participants.count).to eq(2)

      # Create a message for round 2 (future round) - only 1 of 2 participants
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant1,
        role: 'assistant',
        content: 'Future round',
        round_number: 2
      )

      # Should NOT advance because round 2 has 1/2 participants
      conversation.reload
      expect(conversation.current_round).to eq(1)

      # Now add second participant to round 2
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant2,
        role: 'assistant',
        content: 'Round 2 participant 2',
        round_number: 2
      )

      # Now round 2 is complete (2/2), should advance to round 3
      conversation.reload
      expect(conversation.current_round).to eq(3)
    end
  end

  describe 'Query scope validation' do
    before do
      # Create a mix of message types
      create('message', conversation: conversation, role: 'system')
      create('message', conversation: conversation, role: 'user')

      # Regular assistant message (not promoted)
      Message.create!(
        conversation: conversation,
        role: 'assistant',
        content: 'Not finalized'
      )

      # Finalized assistant messages
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant1,
        role: 'assistant',
        content: 'Finalized 1',
        round_number: 1
      )

      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant2,
        role: 'assistant',
        content: 'Finalized 2',
        round_number: 1
      )
    end

    it 'correctly filters messages by type' do
      expect(conversation.messages.count).to eq(5)
      expect(conversation.messages.where(role: 'assistant').count).to eq(3)
      expect(conversation.assistant_messages.count).to eq(2) # Only finalized

      # Verify the association is working correctly
      expect(conversation.assistant_messages).to all(be_a(AssistantMessage))
      expect(conversation.assistant_messages.pluck(:type).uniq).to eq(['AssistantMessage'])
    end
  end
end
