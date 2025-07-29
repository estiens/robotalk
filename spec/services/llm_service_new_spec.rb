# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LlmService, type: :service do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:participant) { conversation.participants.first }
  let(:service) { described_class.new(conversation, participant) }

  describe 'error classes' do
    it 'defines LlmApiError as base error' do
      expect(LlmService::LlmApiError).to be < StandardError
    end

    it 'defines RateLimitError inheriting from LlmApiError' do
      expect(LlmService::RateLimitError).to be < LlmService::LlmApiError
    end
  end

  describe '#initialize' do
    context 'when OpenRouter API key is configured' do
      before do
        allow(ENV).to receive(:fetch).with('OPENROUTER_API_KEY', nil).and_return('test-api-key')
      end

      it 'sets conversation and participant' do
        expect(service.conversation).to eq(conversation)
        expect(service.participant).to eq(participant)
      end
    end

    context 'when OpenRouter API key is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('OPENROUTER_API_KEY', nil).and_return(nil)
      end

      it 'raises an error' do
        expect { described_class.new(conversation, participant) }
          .to raise_error('OpenRouter API key not configured')
      end
    end
  end

  describe '#generate_response' do
    let(:mock_client) { instance_double(OpenRouter::Client) }
    let(:api_response) do
      {
        'choices' => [
          {
            'message' => {
              'content' => 'This is an AI response from the model'
            }
          }
        ],
        'usage' => { 'total_tokens' => 150 },
        'model' => 'test-model',
        'created' => 1234567890
      }
    end

    before do
      allow(ENV).to receive(:fetch).with('OPENROUTER_API_KEY', nil).and_return('test-api-key')
      allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:complete).and_return(api_response)
    end

    it 'returns a hash with correct structure' do
      result = service.generate_response
      
      expect(result).to be_a(Hash)
      expect(result.keys).to match_array([:conversation_participant, :model_id, :content, :metadata])
    end

    it 'returns correct conversation_participant' do
      result = service.generate_response
      expect(result[:conversation_participant]).to eq(participant)
    end

    it 'returns correct model_id' do
      result = service.generate_response
      expect(result[:model_id]).to eq(participant.model_id)
    end

    it 'extracts content from API response' do
      result = service.generate_response
      expect(result[:content]).to eq('This is an AI response from the model')
    end

    it 'includes metadata with model info and response metadata' do
      result = service.generate_response
      
      expect(result[:metadata]).to be_a(Hash)
      expect(result[:metadata][:model_name]).to eq(participant.model_id)
      expect(result[:metadata][:response_metadata]).to include(
        'usage' => { 'total_tokens' => 150 },
        'model' => 'test-model',
        'created' => 1234567890
      )
    end

    it 'creates OpenRouter client and calls complete with correct parameters' do
      messages = [
        { role: 'system', content: participant.system_prompt_with_topic },
        { role: 'user', content: match(/Please introduce yourself/) }
      ]
      
      service.generate_response
      
      expect(OpenRouter::Client).to have_received(:new)
      expect(mock_client).to have_received(:complete).with(
        kind_of(Array),
        hash_including(
          model: [participant.model_id],
          extras: kind_of(Hash)
        )
      )
    end

    context 'with conversation history' do
      let!(:round) { create(:round, conversation: conversation) }
      let!(:existing_message) do
        create(:message, round: round, conversation_participant: participant, 
               content: 'Previous message')
      end

      it 'includes conversation history in messages' do
        expected_messages = [
          { role: 'system', content: participant.system_prompt_with_topic },
          { 
            role: 'assistant', 
            content: 'Previous message',
            name: participant.name.gsub(/[^\w-]/, '_')
          },
          { role: 'user', content: match(/Please continue the discussion/) }
        ]
        
        service.generate_response
        
        expect(mock_client).to have_received(:complete) do |messages, _options|
          expect(messages).to match_array(expected_messages)
        end
      end

      it 'limits conversation history to last 10 messages' do
        # Create 15 messages to test the limit
        15.times do |i|
          create(:message, round: round, conversation_participant: participant,
                 content: "Message #{i}", created_at: i.minutes.ago)
        end

        service.generate_response
        
        expect(mock_client).to have_received(:complete) do |messages, _options|
          # Should have system message + 10 history messages + user prompt = 12 total
          expect(messages.length).to eq(12)
        end
      end
    end

    context 'different response formats' do
      context 'with standard OpenAI format' do
        it 'extracts content correctly' do
          result = service.generate_response
          expect(result[:content]).to eq('This is an AI response from the model')
        end
      end

      context 'with alternative response format' do
        let(:alt_response) { { 'message' => { 'content' => 'Alternative format' } } }
        
        before do
          allow(mock_client).to receive(:complete).and_return(alt_response)
        end

        it 'extracts content from alternative format' do
          result = service.generate_response
          expect(result[:content]).to eq('Alternative format')
        end
      end

      context 'with direct content format' do
        let(:direct_response) { { 'content' => 'Direct content' } }
        
        before do
          allow(mock_client).to receive(:complete).and_return(direct_response)
        end

        it 'extracts direct content' do
          result = service.generate_response
          expect(result[:content]).to eq('Direct content')
        end
      end

      context 'with no extractable content' do
        let(:empty_response) { {} }
        
        before do
          allow(mock_client).to receive(:complete).and_return(empty_response)
        end

        it 'returns default error message' do
          result = service.generate_response
          expect(result[:content]).to eq('No content in response')
        end
      end
    end

    context 'when API call raises an exception' do
      before do
        allow(mock_client).to receive(:complete).and_raise(StandardError.new('API connection failed'))
      end

      it 'returns error data instead of raising' do
        result = service.generate_response
        
        expect(result).to be_a(Hash)
        expect(result[:conversation_participant]).to eq(participant)
        expect(result[:model_id]).to eq(participant.model_id)
        expect(result[:content]).to eq('Sorry, I encountered an error generating my response.')
        expect(result[:metadata]).to include(
          error: 'API connection failed',
          is_error: true
        )
      end

      it 'logs the error' do
        allow(Rails.logger).to receive(:error)
        
        service.generate_response
        
        expect(Rails.logger).to have_received(:error)
          .with(match(/\[LlmService\] Error: API connection failed/))
      end
    end

    context 'message building' do
      it 'builds correct system message' do
        service.generate_response
        
        expect(mock_client).to have_received(:complete) do |messages, _options|
          system_message = messages.first
          expect(system_message[:role]).to eq('system')
          expect(system_message[:content]).to eq(participant.system_prompt_with_topic)
        end
      end

      context 'with empty conversation' do
        it 'builds introduction user message' do
          service.generate_response
          
          expect(mock_client).to have_received(:complete) do |messages, _options|
            user_message = messages.last
            expect(user_message[:role]).to eq('user')
            expect(user_message[:content]).to include('Please introduce yourself')
            expect(user_message[:content]).to include(conversation.conversation_topic)
          end
        end
      end

      context 'with existing messages' do
        let!(:round) { create(:round, conversation: conversation) }
        let!(:existing_message) do
          create(:message, round: round, conversation_participant: participant)
        end

        it 'builds continuation user message' do
          service.generate_response
          
          expect(mock_client).to have_received(:complete) do |messages, _options|
            user_message = messages.last
            expect(user_message[:role]).to eq('user')
            expect(user_message[:content]).to include('Please continue the discussion')
            expect(user_message[:content]).to include(conversation.conversation_topic)
          end
        end
      end

      it 'sanitizes participant names for API' do
        participant.update!(name: 'Test Participant!')
        service.generate_response
        
        expect(mock_client).to have_received(:complete) do |messages, _options|
          # Find message with name field
          named_message = messages.find { |m| m[:name] }
          expect(named_message[:name]).to eq('Test_Participant_') if named_message
        end
      end
    end
  end
end