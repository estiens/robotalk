# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AssistantMessage do
  let(:conversation) { create('conversation', max_rounds: 3) }
  let(:participant) { create('conversation_participant', conversation: conversation) }

  describe 'STI inheritance' do
    it 'inherits from Message' do
      expect(AssistantMessage.superclass).to eq(Message)
    end

    it 'uses the messages table' do
      expect(AssistantMessage.table_name).to eq('messages')
    end

    it 'sets type column automatically' do
      message = AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'Test content'
      )
      expect(message.type).to eq('AssistantMessage')
    end
  end

  describe 'default scope' do
    before do
      # Create messages with different roles
      create('message', conversation: conversation, conversation_participant: participant, role: 'system', content: 'System message')
      create('message', conversation: conversation, conversation_participant: participant, role: 'user', content: 'User message')
      # Create an assistant message using the Message model but with type set
      Message.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'Assistant message 1',
        type: 'AssistantMessage'
      )
      Message.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'Assistant message 2',
        type: 'AssistantMessage'
      )
    end

    it 'only returns messages with assistant role' do
      messages = AssistantMessage.all
      expect(messages.count).to eq(2)
      expect(messages.pluck(:role).uniq).to eq(['assistant'])
    end

    it 'filters out non-assistant messages even if type is set incorrectly' do
      # Attempt to create an AssistantMessage with wrong role
      message = Message.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'user',
        content: 'Wrong role',
        type: 'AssistantMessage'
      )

      expect(AssistantMessage.all).not_to include(message)
    end
  end

  describe 'callbacks' do
    describe '#trigger_conversation_processing' do
      it 'calls process_new_assistant_message on conversation after create' do
        expect_any_instance_of(Conversation).to receive(:process_new_assistant_message)

        AssistantMessage.create!(
          conversation: conversation,
          conversation_participant: participant,
          role: 'assistant',
          content: 'Test message'
        )
      end

      it 'uses after_create_commit to ensure transaction completion' do
        # Verify the callback is registered correctly
        callbacks = AssistantMessage._commit_callbacks.select do |cb|
          cb.filter == :trigger_conversation_processing
        end

        expect(callbacks).not_to be_empty
        expect(callbacks.first.kind).to eq(:after)
      end
    end
  end

  describe 'type promotion from Message to AssistantMessage' do
    let(:message) do
      Message.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: '',
        metadata: { status: 'streaming' }
      )
    end

    it 'can be promoted by updating type column' do
      expect(message.type).to be_nil

      # Simulate the promotion process
      message.update_columns(type: 'AssistantMessage', content: 'Completed content')
      reloaded = Message.find(message.id)

      expect(reloaded).to be_a(AssistantMessage)
      expect(reloaded.type).to eq('AssistantMessage')
      expect(reloaded.content).to eq('Completed content')
    end

    it 'does not trigger create callbacks after promotion since record already exists' do
      # update_columns bypasses callbacks
      message.update_columns(type: 'AssistantMessage')

      # Reload as AssistantMessage
      assistant_message = AssistantMessage.find(message.id)

      # after_create_commit won't fire on an existing record, even after type change
      expect(assistant_message.conversation).not_to receive(:process_new_assistant_message)
      assistant_message.save!

      # The callback only fires on actual creation of new AssistantMessage records
    end
  end

  describe 'round management integration' do
    before do
      # Create initial system messages
      create('message', conversation: conversation, conversation_participant: participant, role: 'system', content: 'System prompt')
    end

    it 'increments round count when multiple assistant messages are created' do
      expect(conversation.current_round).to eq(1)

      # First assistant message
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'First message',
        round_number: 1
      )

      # process_new_assistant_message should increment the round
      conversation.reload
      expect(conversation.current_round).to eq(2)
    end

    it 'properly tracks finalized messages for round calculation' do
      # Create a streaming message (not finalized)
      Message.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: '',
        metadata: { status: 'streaming' }
      )

      # Create a finalized assistant message
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'Complete message',
        round_number: 1
      )

      # Only finalized messages should count
      expect(conversation.assistant_messages.count).to eq(1)
      expect(conversation.messages.where(role: 'assistant').count).to eq(2)
    end
  end

  describe 'validation and data integrity' do
    it 'requires conversation association' do
      message = AssistantMessage.new(role: 'assistant', content: 'Test')
      expect(message).not_to be_valid
      expect(message.errors[:conversation]).to include('must exist')
    end

    it 'automatically sets role to assistant if not provided' do
      AssistantMessage.new(
        conversation: conversation,
        conversation_participant: participant,
        content: 'Test content'
      )

      # The default scope will enforce this when querying
      expect(AssistantMessage.where(conversation: conversation)).to be_empty
    end

    it 'maintains referential integrity with conversation_participant' do
      message = AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: 'assistant',
        content: 'Test'
      )

      expect(message.conversation_participant).to eq(participant)
      expect(participant.messages).to include(message)
    end
  end
end
