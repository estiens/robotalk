# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoundService, type: :service do
  let(:user) { User.create!(email: "test-#{SecureRandom.hex(4)}@example.com", password: 'password') }
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
  let(:alice) { conversation.participants.find_by(name: 'Alice') }
  let(:bob) { conversation.participants.find_by(name: 'Bob') }
  let(:service) { RoundService.new(conversation) }

  let(:mock_client) { double('OpenRouter::Client') }
  let(:mock_response) { { 'choices' => [{ 'message' => { 'content' => 'Test response' } }] } }

  before do
    allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:complete).and_return(mock_response)
  end

  describe '#perform_round!' do
    it 'has each participant speak once in turn order' do
      expect(LlmService).to receive(:new).with(conversation, alice).and_call_original
      expect(LlmService).to receive(:new).with(conversation, bob).and_call_original

      service.perform_round!

      expect(conversation.messages.count).to eq(2)
      expect(conversation.current_round).to eq(2)

      messages = conversation.messages.order(:created_at)
      expect(messages[0].conversation_participant).to eq(alice)
      expect(messages[1].conversation_participant).to eq(bob)
    end

    it 'completes full round even when max_rounds is reached' do
      # Set up a conversation with max_rounds of 1
      conversation.update!(max_rounds: 1)

      # Both participants should speak to complete the round
      expect(LlmService).to receive(:new).with(conversation, alice).and_call_original
      expect(LlmService).to receive(:new).with(conversation, bob).and_call_original

      service.perform_round!

      expect(conversation.messages.count).to eq(2)
      expect(conversation.current_round).to eq(2) # Advanced past max_rounds of 1
      expect(conversation.status).to eq('complete')
    end

    it 'advances to next round after all participants speak' do
      initial_round = conversation.current_round

      service.perform_round!

      expect(conversation.current_round).to eq(initial_round + 1)
    end
  end

  describe '#generate_full_conversation!' do
    it 'performs complete conversation until max_rounds' do
      service.generate_full_conversation!

      expect(conversation.status).to eq('complete')
      expect(conversation.current_round).to eq(3) # Past max_rounds of 2
      expect(conversation.messages.count).to eq(4) # 2 rounds × 2 participants

      # Verify message order
      messages = conversation.messages.order(:created_at)
      expect(messages[0].conversation_participant).to eq(alice) # Round 1
      expect(messages[1].conversation_participant).to eq(bob)   # Round 1
      expect(messages[2].conversation_participant).to eq(alice) # Round 2
      expect(messages[3].conversation_participant).to eq(bob)   # Round 2
    end

    it 'sets status to in_progress during execution' do
      allow(service).to receive(:perform_round!).and_wrap_original do |method|
        expect(conversation.status).to eq('in_progress')
        method.call
      end

      service.generate_full_conversation!
    end

    it 'handles errors and sets status to failed' do
      allow(service).to receive(:perform_round!).and_raise(StandardError.new('API Error'))

      expect do
        service.generate_full_conversation!
      end.to raise_error(StandardError, 'API Error')

      expect(conversation.status).to eq('failed')
    end

    it 'completes when conversation reaches max_rounds' do
      conversation.update!(max_rounds: 1)

      service.generate_full_conversation!

      expect(conversation.status).to eq('complete')
      expect(conversation.current_round).to eq(2) # Past max_rounds of 1
      expect(conversation.messages.count).to eq(2) # 1 round × 2 participants
    end
  end

  describe '#have_current_speaker_respond!' do
    it 'CRITICAL BUG: should NOT advance round until ALL participants speak' do
      # This test demonstrates the critical bug: have_current_speaker_respond! 
      # advances the round immediately after ANY participant speaks,
      # breaking multi-participant conversations

      # Start with a fresh conversation in round 1
      expect(conversation.current_round).to eq(1)
      expect(conversation.next_speaker).to eq(alice)

      # Alice speaks first 
      service.have_current_speaker_respond!
      conversation.reload

      # CRITICAL BUG TEST: Round should still be 1 since Bob hasn't spoken yet
      
      expect(conversation.current_round).to eq(1), "Round should remain 1 until ALL participants speak"
      expect(conversation.next_speaker).to eq(bob), "Bob should be next to speak in round 1"

      # Bob speaks second to complete the round
      service.have_current_speaker_respond!
      conversation.reload

      # NOW the round should advance to 2
      expect(conversation.current_round).to eq(2), "Round should advance to 2 after BOTH participants speak"
      expect(conversation.next_speaker).to eq(alice), "Alice should be first speaker in round 2"
    end

    it 'preserves individual speaker responses while maintaining proper round logic' do
      # This ensures that have_current_speaker_respond! can be called individually
      # while still maintaining proper round boundaries

      initial_round = conversation.current_round
      
      # First speaker in the round
      first_speaker = conversation.next_speaker
      service.have_current_speaker_respond!
      conversation.reload

      # Round should not advance yet
      expect(conversation.current_round).to eq(initial_round)
      
      # Second speaker should be different
      second_speaker = conversation.next_speaker
      expect(second_speaker).not_to eq(first_speaker)
      
      service.have_current_speaker_respond!
      conversation.reload

      # Now round should advance
      expect(conversation.current_round).to eq(initial_round + 1)
    end
  end

  describe 'round advancement logic' do
    it 'advances round after all participants speak' do
      # Simulate first round
      Message.create!(
        conversation: conversation,
        conversation_participant: alice,
        role: Message::ROLE_ASSISTANT,
        model_id: alice.model_id,
        round_number: 1,
        content: 'Alice speaks'
      )

      Message.create!(
        conversation: conversation,
        conversation_participant: bob,
        role: Message::ROLE_ASSISTANT,
        model_id: bob.model_id,
        round_number: 1,
        content: 'Bob speaks'
      )

      # After round 1 is complete, conversation should be at round 2
      conversation.update!(current_round: 2)
      
      # Performing round 2 should advance to round 3
      service.perform_round!

      expect(conversation.current_round).to eq(3) # Advanced from 2 to 3
    end

    it 'marks conversation complete when past max_rounds' do
      conversation.update!(current_round: 2, max_rounds: 2)

      service.send(:advance_round!)

      expect(conversation.current_round).to eq(3)
      expect(conversation.status).to eq('complete')
    end
  end
end
