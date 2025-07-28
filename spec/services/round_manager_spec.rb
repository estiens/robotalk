# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoundManager, type: :service do
  let(:user) { create(:user) }
  let(:conversation) { Conversation.create!(user: user, max_rounds: 3, conversation_topic: 'Test Topic') }
  let(:round_manager) { RoundManager.new(conversation) }

  before do
    conversation.participants.create!(model_id: 'openai/gpt-4', name: 'Assistant 1', turn_order: 1)
    conversation.participants.create!(model_id: 'anthropic/claude-3-haiku', name: 'Assistant 2', turn_order: 2)
    conversation.participants.create!(model_id: 'deepseek/deepseek-r1', name: 'Assistant 3', turn_order: 3)
  end

  describe 'conversation#current_round' do
    it 'starts at 1 when no assistant messages exist' do
      expect(conversation.current_round).to eq(1)
    end


    it 'handles zero participants gracefully' do
      conversation.participants.destroy_all
      expect(conversation.current_round).to eq(1)
    end
  end

  describe '#next_speaker' do
    it 'returns first participant when no assistant messages exist' do
      next_speaker = round_manager.next_speaker
      expect(next_speaker).to eq(conversation.participants.ordered.first)
      expect(next_speaker.turn_order).to eq(1)
    end

    it 'returns second participant after first has spoken' do
      first_participant = conversation.participants.ordered.first
      conversation.messages.create!(
        role: 'assistant',
        content: 'First message',
        model_id: first_participant.model_id,
        conversation_participant: first_participant
      )

      next_speaker = round_manager.next_speaker
      expect(next_speaker.turn_order).to eq(2)
    end


    it 'returns nil if message has no conversation_participant' do
      conversation.messages.create!(role: 'assistant', content: 'Message', model_id: 'unknown/model',
                                    conversation_participant: nil)
      expect(round_manager.next_speaker).to eq(conversation.participants.ordered.first)
    end
  end
end
