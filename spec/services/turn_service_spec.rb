# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TurnService, type: :service do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:round) { create(:round, :in_progress, conversation: conversation) }
  let(:participant) { conversation.participants.first }
  let(:service) { described_class.new(round, participant) }

  describe '#initialize' do
    it 'sets up the round, participant, and logger' do
      expect(service.round).to eq(round)
      expect(service.participant).to eq(participant)
      expect(service.logger).to eq(Rails.logger)
    end
    
    it 'validates participant belongs to conversation' do
      other_conversation = create(:conversation, :with_participants)
      other_participant = other_conversation.participants.first
      
      expect { described_class.new(round, other_participant) }.to raise_error(
        ArgumentError, 
        /Participant #{other_participant.id} does not belong to conversation #{round.conversation.id}/
      )
    end
  end

  describe '#execute' do
    let(:llm_service_double) { instance_double(LlmService) }
    let(:message_data) do
      {
        conversation_participant: participant,
        model_id: participant.model_id,
        content: 'Test AI response from the model',
        metadata: {
          model_name: participant.model_id,
          response_metadata: { 'usage' => { 'tokens' => 150 } }
        }
      }
    end

    before do
      allow(LlmService).to receive(:new).with(conversation, participant).and_return(llm_service_double)
      allow(llm_service_double).to receive(:generate_response).and_return(message_data)
    end

    it 'creates a new LlmService with correct parameters' do
      service.execute
      expect(LlmService).to have_received(:new).with(conversation, participant)
    end

    it 'generates a response using LlmService' do
      service.execute
      expect(llm_service_double).to have_received(:generate_response)
    end

    it 'creates a Message record with the returned data' do
      expect { service.execute }.to change(Message, :count).by(1)
      
      message = Message.last
      expect(message.round).to eq(round)
      expect(message.conversation_participant).to eq(participant)
      expect(message.model_id).to eq(participant.model_id)
      expect(message.content).to eq('Test AI response from the model')
      expect(message.metadata).to eq(message_data[:metadata].stringify_keys)
    end

    it 'updates the round last_activity_at timestamp' do
      freeze_time do
        service.execute
        expect(round.reload.last_activity_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'returns the created message' do
      result = service.execute
      expect(result).to be_a(Message)
      expect(result.content).to eq('Test AI response from the model')
    end

    it 'logs the participant response details' do
      allow(Rails.logger).to receive(:info)
      
      service.execute
      
      expect(Rails.logger).to have_received(:info)
        .with(match(/\[TurnService\] #{participant.name} response: \d+ chars/))
    end

    context 'with error response data' do
      let(:error_message_data) do
        {
          conversation_participant: participant,
          model_id: participant.model_id,
          content: 'Sorry, I encountered an error generating my response.',
          metadata: { error: 'API timeout', is_error: true }
        }
      end

      before do
        allow(llm_service_double).to receive(:generate_response).and_return(error_message_data)
      end

      it 'creates an error message record' do
        expect { service.execute }.to change(Message, :count).by(1)
        
        message = Message.last
        expect(message.content).to eq('Sorry, I encountered an error generating my response.')
        expect(message.error_message?).to be true
        expect(message.metadata['error']).to eq('API timeout')
      end
    end

    context 'transaction behavior' do
      it 'executes within a transaction' do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original
        service.execute
      end

      it 'rolls back if message creation fails' do
        # Force a validation error by making content too long or invalid
        invalid_data = message_data.merge(content: nil)
        allow(llm_service_double).to receive(:generate_response).and_return(invalid_data)
        
        expect { service.execute }.to raise_error(ActiveRecord::RecordInvalid)
        expect(Message.count).to eq(0)
        
        # Round should not be updated if transaction fails
        original_activity_time = round.last_activity_at
        expect(round.reload.last_activity_at).to eq(original_activity_time)
      end
    end

    context 'when LlmService raises an exception' do
      before do
        allow(llm_service_double).to receive(:generate_response)
          .and_raise(StandardError.new('LLM API failure'))
      end

      it 'does not create a message record' do
        expect { service.execute }.to raise_error(StandardError, 'LLM API failure')
        expect(Message.count).to eq(0)
      end

      it 'does not update round activity timestamp' do
        original_activity_time = round.last_activity_at
        
        expect { service.execute }.to raise_error(StandardError)
        expect(round.reload.last_activity_at).to eq(original_activity_time)
      end

      it 'rolls back the entire transaction' do
        expect { service.execute }.to raise_error(StandardError)
        expect(Message.count).to eq(0)
      end
    end

    context 'with different participants' do
      let(:participant2) { conversation.participants.second }
      let(:service2) { described_class.new(round, participant2) }
      let(:llm_service_double2) { instance_double(LlmService) }
      let(:participant2_data) do
        message_data.merge(
          conversation_participant: participant2,
          model_id: participant2.model_id,
          content: 'Response from participant 2'
        )
      end

      before do
        allow(LlmService).to receive(:new).with(conversation, participant2).and_return(llm_service_double2)
        allow(llm_service_double2).to receive(:generate_response).and_return(participant2_data)
      end

      it 'creates messages for different participants correctly' do
        # Create message for first participant
        message1 = service.execute
        
        # Create message for second participant  
        message2 = service2.execute
        
        expect(message1.conversation_participant).to eq(participant)
        expect(message2.conversation_participant).to eq(participant2)
        expect(message1.round).to eq(round)
        expect(message2.round).to eq(round)
      end
    end

    context 'message metadata handling' do
      let(:complex_metadata) do
        {
          model_name: 'test-model',
          response_metadata: {
            'usage' => { 'prompt_tokens' => 50, 'completion_tokens' => 100 },
            'model' => 'gpt-4',
            'created' => 1234567890
          },
          custom_field: 'custom_value'
        }
      end
      
      let(:message_with_metadata) do
        message_data.merge(metadata: complex_metadata)
      end

      before do
        allow(llm_service_double).to receive(:generate_response).and_return(message_with_metadata)
      end

      it 'preserves all metadata fields' do
        service.execute
        
        message = Message.last
        expect(message.metadata).to eq(complex_metadata.stringify_keys)
        expect(message.metadata['model_name']).to eq('test-model')
        expect(message.metadata['response_metadata']['usage']['prompt_tokens']).to eq(50)
        expect(message.metadata['custom_field']).to eq('custom_value')
      end
    end
  end
end