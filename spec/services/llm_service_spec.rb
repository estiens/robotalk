# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LlmService, type: :service do
  let(:user) { User.create!(email: 'test@example.com', password: 'password') }
  let(:conversation) do
    Conversation.create!(
      user: user,
      conversation_topic: 'AI Safety',
      max_rounds: 2,
      participants_attributes: [
        { name: 'Alice', model_id: 'openai/gpt-4o-mini', turn_order: 1 },
        { name: 'Bob', model_id: 'anthropic/claude-3-haiku', turn_order: 2 }
      ]
    )
  end
  let(:participant) { conversation.participants.first }
  let(:service) { LlmService.new(conversation, participant) }

  let(:mock_client) { double('OpenRouter::Client') }
  let(:mock_response) { { 'choices' => [{ 'message' => { 'content' => 'AI safety is crucial for our future.' } }] } }

  before do
    allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:complete).and_return(mock_response)
  end

  describe '#generate_response' do
    it 'creates OpenRouter client and calls complete with correct model' do
      expect(OpenRouter::Client).to receive(:new)
      expect(mock_client).to receive(:complete).with(
        anything,
        model: ['openai/gpt-4o-mini'],
        extras: {}
      )

      service.generate_response
    end

    it 'includes system prompt in messages' do
      expect(mock_client).to receive(:complete).with(
        array_including(
          hash_including(role: 'system', content: participant.system_prompt_with_topic)
        ),
        anything
      )

      service.generate_response
    end

    context 'with empty conversation' do
      it 'includes introduction prompt in user message' do
        expected_prompt = 'Please introduce yourself and start discussing: AI Safety'

        expect(mock_client).to receive(:complete).with(
          array_including(
            hash_including(role: 'user', content: expected_prompt)
          ),
          anything
        )

        service.generate_response
      end
    end

    context 'with existing conversation history' do
      before do
        AssistantMessage.create!(
          conversation: conversation,
          conversation_participant: conversation.participants.last,
          role: Message::ROLE_ASSISTANT,
          model_id: 'anthropic/claude-3-haiku',
          round_number: 1,
          content: 'Previous message content'
        )
      end

      it 'includes conversation history in messages' do
        expect(mock_client).to receive(:complete).with(
          array_including(
            hash_including(role: 'assistant', content: 'Previous message content', name: 'Bob')
          ),
          anything
        )

        service.generate_response
      end
    end

    it 'creates AssistantMessage with correct attributes' do
      message = service.generate_response

      expect(message).to be_a(AssistantMessage)
      expect(message.conversation).to eq(conversation)
      expect(message.conversation_participant).to eq(participant)
      expect(message.role).to eq(Message::ROLE_ASSISTANT)
      expect(message.model_id).to eq(participant.model_id)
      expect(message.round_number).to eq(conversation.current_round)
      expect(message.content).to eq('AI safety is crucial for our future.')
    end

    it 'includes metadata in created message' do
      message = service.generate_response

      expect(message.metadata).to be_a(Hash)
      expect(message.metadata['model_name']).to eq(participant.model_id)
    end

    context 'when LLM call fails' do
      before do
        allow(mock_client).to receive(:complete).and_raise(StandardError.new('API Error'))
      end

      it 'creates error message and re-raises' do
        expect do
          service.generate_response
        end.to raise_error(StandardError, 'API Error')

        # Should still create a message with error content
        message = conversation.messages.last
        expect(message.content).to eq('Sorry, I encountered an error generating my response.')
        expect(message.metadata['error']).to eq('API Error')
      end
    end
  end

  # Removed provider extraction - OpenRouter handles this automatically

  describe '#build_messages' do
    it 'includes system message' do
      messages = service.send(:build_messages)
      system_message = messages.find { |m| m[:role] == 'system' }

      expect(system_message).to be_present
      expect(system_message[:content]).to eq(participant.system_prompt_with_topic)
    end

    context 'with existing conversation' do
      before do
        AssistantMessage.create!(
          conversation: conversation,
          conversation_participant: participant,
          role: Message::ROLE_ASSISTANT,
          model_id: participant.model_id,
          round_number: 1,
          content: 'Hello everyone!'
        )
      end

      it 'includes assistant messages with names' do
        messages = service.send(:build_messages)
        assistant_message = messages.find { |m| m[:role] == 'assistant' }

        expect(assistant_message).to be_present
        expect(assistant_message[:content]).to eq('Hello everyone!')
        expect(assistant_message[:name]).to eq('Alice')
      end
    end
  end

  describe '#build_user_message' do
    context 'with empty conversation' do
      it 'returns introduction message' do
        message = service.send(:build_user_message)
        expect(message).to eq('Please introduce yourself and start discussing: AI Safety')
      end
    end

    context 'with existing messages' do
      before do
        AssistantMessage.create!(
          conversation: conversation,
          conversation_participant: participant,
          role: Message::ROLE_ASSISTANT,
          model_id: participant.model_id,
          round_number: 1,
          content: 'Hello everyone!'
        )
      end

      it 'returns continue message' do
        message = service.send(:build_user_message)
        expect(message).to include('continue the discussion')
        expect(message).to include('AI Safety')
      end
    end
  end
end
