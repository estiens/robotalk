# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationsController, type: :controller do
  let(:user) { User.create!(email: "deadlock-#{SecureRandom.hex(4)}@example.com", password: 'password') }
  let(:conversation) do
    Conversation.create!(
      user: user,
      conversation_topic: 'Deadlock Test',
      max_rounds: 2,
      participants_attributes: [
        { name: 'Alice', model_id: 'openai/gpt-4o-mini', turn_order: 1 },
        { name: 'Bob', model_id: 'anthropic/claude-3-haiku', turn_order: 2 }
      ]
    )
  end

  before do
    # Manual session setup for controller specs
    session[:user_id] = user.id
    allow(controller).to receive(:current_user).and_return(user)
  end

  describe 'conversation state deadlock bug' do
    it 'CRITICAL BUG: should recover from LLM failures and not leave conversation stuck in in_progress state' do
      # Start with pending conversation
      expect(conversation.status).to eq('pending')
      expect(conversation.can_start?).to be(true)

      # Mock LLM service to fail
      mock_client = double('OpenRouter::Client')
      allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:complete).and_raise(StandardError.new('API timeout'))

      # Attempt to start conversation (this should fail)
      post :start, params: { id: conversation.id }
      conversation.reload

      # CRITICAL BUG: Conversation should not be permanently stuck
      # It should either:
      # 1. Stay in 'pending' state so user can retry, OR  
      # 2. Go to 'failed' state with ability to reset to 'pending'
      expect(conversation.status).not_to eq('in_progress'), 
        "Conversation should not be stuck in 'in_progress' after LLM failure"

      # User should be able to retry after failure
      expect(conversation.can_start? || conversation.status == 'failed').to be(true),
        "User should be able to retry or reset after LLM failure"
    end

    it 'should handle continue action failures without deadlock' do
      # Manually set up a conversation that can continue
      conversation.update!(status: 'in_progress')
      Message.create!(
        conversation: conversation,
        conversation_participant: conversation.participants.first,
        role: Message::ROLE_ASSISTANT,
        model_id: conversation.participants.first.model_id,
        round_number: 1,
        content: 'First message'
      )

      expect(conversation.can_continue?).to be(true)

      # Mock LLM service to fail on continue
      mock_client = double('OpenRouter::Client')
      allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:complete).and_raise(StandardError.new('Network error'))

      # Attempt to continue conversation (this should fail)
      post :continue, params: { id: conversation.id }
      conversation.reload

      # Conversation should still be recoverable
      expect(conversation.status).not_to eq('in_progress'), 
        "Conversation should not remain stuck in 'in_progress' after continue failure"
      
      # Should either be retryable or failed with recovery option
      expect(conversation.can_continue? || conversation.status == 'failed').to be(true),
        "User should be able to retry or recover after continue failure"
    end

    it 'should provide a way to reset failed conversations' do
      # Simulate a failed conversation
      conversation.update!(status: 'failed')

      # Test the reset functionality
      expect(conversation.reset!).to be(true)
      expect(conversation.status).to eq('pending')
      expect(conversation.can_start?).to be(true)
    end

    it 'should allow resetting completed conversations' do
      # Simulate a completed conversation
      conversation.update!(status: 'complete')

      # Should be able to reset and restart
      expect(conversation.reset!).to be(true)
      expect(conversation.status).to eq('pending')
      expect(conversation.can_start?).to be(true)
    end

    it 'should not allow resetting in_progress conversations' do
      # In-progress conversations should not be reset (they should complete normally)
      conversation.update!(status: 'in_progress')

      expect(conversation.reset!).to be(false)
      expect(conversation.status).to eq('in_progress')
    end
  end
end