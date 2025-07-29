# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationBroadcaster do
  let(:conversation) { create(:conversation, :with_participants) }
  let(:participant) { conversation.participants.first }
  let(:round) { create(:round, conversation: conversation) }
  let(:message) { create(:message, round: round, conversation_participant: participant) }
  
  describe '#initialize' do
    it 'initializes with a conversation and default interactive mode' do
      broadcaster = described_class.new(conversation)
      
      expect(broadcaster.conversation).to eq(conversation)
      expect(broadcaster.mode).to eq(:interactive)
    end
    
    it 'accepts a custom mode' do
      broadcaster = described_class.new(conversation, mode: :background)
      
      expect(broadcaster.mode).to eq(:background)
    end
    
    it 'raises error for invalid mode' do
      expect {
        described_class.new(conversation, mode: :invalid)
      }.to raise_error(ArgumentError, /Invalid mode: invalid/)
    end
    
    it 'raises error for nil conversation' do
      expect {
        described_class.new(nil)
      }.to raise_error(ArgumentError, /Conversation cannot be nil/)
    end
  end
  
  describe '#broadcast_participant_started' do
    let(:broadcaster) { described_class.new(conversation) }
    
    context 'in interactive mode' do
      it 'broadcasts loading state with participant details' do
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
          [conversation, 'messages'],
          target: 'message-loading',
          partial: 'shared/streaming_indicator',
          locals: { 
            model_name: participant.model_id, 
            participant_name: participant.name 
          }
        )
        
        broadcaster.broadcast_participant_started(participant)
      end
      
      it 'handles nil participant gracefully' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)
        expect(Rails.logger).to receive(:warn).with(/Attempted to broadcast with nil participant/)
        
        broadcaster.broadcast_participant_started(nil)
      end
    end
    
    context 'in background mode' do
      let(:broadcaster) { described_class.new(conversation, mode: :background) }
      
      it 'does not broadcast anything' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)
        
        broadcaster.broadcast_participant_started(participant)
      end
    end
  end
  
  describe '#broadcast_message_created' do
    let(:broadcaster) { described_class.new(conversation) }
    
    context 'in interactive mode' do
      it 'broadcasts message append with correct locals' do
        allow(conversation.messages).to receive(:count).and_return(5)
        
        expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
          [conversation, 'messages'],
          target: 'conversation-messages',
          partial: 'conversations/message',
          locals: { 
            message: message, 
            conversation: conversation, 
            index: 4  # count - 1
          }
        )
        
        broadcaster.broadcast_message_created(message)
      end
      
      it 'handles first message correctly (index 0)' do
        allow(conversation.messages).to receive(:count).and_return(1)
        
        expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
          [conversation, 'messages'],
          hash_including(locals: hash_including(index: 0))
        )
        
        broadcaster.broadcast_message_created(message)
      end
      
      it 'handles nil message gracefully' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
        expect(Rails.logger).to receive(:warn).with(/Attempted to broadcast with nil message/)
        
        broadcaster.broadcast_message_created(nil)
      end
      
      it 'verifies message belongs to conversation' do
        other_conversation = create(:conversation, :with_participants)
        other_round = create(:round, conversation: other_conversation)
        other_message = create(:message, round: other_round, conversation_participant: other_conversation.participants.first)
        
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
        expect(Rails.logger).to receive(:error).with(/Message does not belong to conversation/)
        
        broadcaster.broadcast_message_created(other_message)
      end
    end
    
    context 'in background mode' do
      let(:broadcaster) { described_class.new(conversation, mode: :background) }
      
      it 'does not broadcast anything' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
        
        broadcaster.broadcast_message_created(message)
      end
    end
  end
  
  describe '#broadcast_round_completed' do
    let(:broadcaster) { described_class.new(conversation) }
    
    context 'in interactive mode' do
      it 'clears loading indicator and updates conversation frame' do
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
          [conversation, 'messages'],
          target: 'message-loading',
          html: ''
        ).ordered
        
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
          [conversation, 'messages'],
          target: 'conversation',
          partial: 'conversations/conversation_frame',
          locals: { conversation: conversation }
        ).ordered
        
        broadcaster.broadcast_round_completed
      end
      
      it 'continues even if first broadcast fails' do
        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(StandardError, 'Network error')
        
        expect(Rails.logger).to receive(:error).with(/Failed to clear loading indicator/)
        expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        
        expect { broadcaster.broadcast_round_completed }.not_to raise_error
      end
      
      it 'logs error if conversation frame update fails' do
        allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, 'Render error')
        
        expect(Rails.logger).to receive(:error).with(/Failed to update conversation frame/)
        
        expect { broadcaster.broadcast_round_completed }.not_to raise_error
      end
    end
    
    context 'in background mode' do
      let(:broadcaster) { described_class.new(conversation, mode: :background) }
      
      it 'does not broadcast anything' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
        
        broadcaster.broadcast_round_completed
      end
    end
  end
  
  describe '#broadcast_error' do
    let(:broadcaster) { described_class.new(conversation) }
    let(:error_message) { 'Something went wrong' }
    
    context 'in interactive mode' do
      it 'clears loading and broadcasts error message' do
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
          [conversation, 'messages'],
          target: 'message-loading',
          html: ''
        ).ordered
        
        expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
          [conversation, 'messages'],
          target: 'conversation-messages',
          partial: 'shared/error_message',
          locals: { error: error_message }
        ).ordered
        
        broadcaster.broadcast_error(error_message)
      end
      
      it 'handles nil error message' do
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
          [conversation, 'messages'],
          hash_including(locals: { error: 'An unknown error occurred' })
        )
        
        broadcaster.broadcast_error(nil)
      end
      
      it 'sanitizes error message' do
        malicious_error = '<script>alert("XSS")</script>Error'
        
        expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).with(
          [conversation, 'messages'],
          hash_including(locals: { error: 'Error' })
        )
        
        broadcaster.broadcast_error(malicious_error)
      end
    end
    
    context 'in background mode' do
      let(:broadcaster) { described_class.new(conversation, mode: :background) }
      
      it 'does not broadcast anything' do
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)
        expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
        
        broadcaster.broadcast_error(error_message)
      end
    end
  end
  
  describe 'integration with RoundOrchestrator callbacks' do
    let(:broadcaster) { described_class.new(conversation) }
    
    it 'can be used in turn_started callback' do
      callback = ->(payload) { broadcaster.broadcast_participant_started(payload[:participant]) }
      
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      callback.call({ participant: participant })
    end
    
    it 'can be used in turn_completed callback' do
      callback = ->(payload) { broadcaster.broadcast_message_created(payload[:result]) }
      
      allow(conversation.messages).to receive(:count).and_return(1)
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      callback.call({ result: message })
    end
    
    it 'can be used in round_completed callback' do
      callback = ->(payload) { broadcaster.broadcast_round_completed }
      
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      callback.call({})
    end
  end
  
  describe 'error resilience' do
    let(:broadcaster) { described_class.new(conversation) }
    
    it 'logs and continues when Turbo broadcasting fails' do
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(StandardError, 'Redis error')
      
      expect(Rails.logger).to receive(:error).with(/Broadcasting failed/)
      expect { broadcaster.broadcast_participant_started(participant) }.not_to raise_error
    end
    
    it 'handles ActionView rendering errors gracefully' do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to).and_raise(StandardError, 'Template error')
      allow(conversation.messages).to receive(:count).and_return(1)
      
      expect(Rails.logger).to receive(:error).with(/Broadcasting failed/)
      expect { broadcaster.broadcast_message_created(message) }.not_to raise_error
    end
  end
  
  describe 'performance considerations' do
    let(:broadcaster) { described_class.new(conversation) }
    
    it 'uses message count efficiently for indexing' do
      # Should use count through rounds, not loading all messages
      expect_any_instance_of(Conversation).to receive_message_chain(:messages, :count).and_return(10)
      
      broadcaster.broadcast_message_created(message)
    end
  end
end