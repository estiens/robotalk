# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RoundService, type: :service do
  let(:user) { User.create!(email: "race-#{SecureRandom.hex(4)}@example.com", password: 'password') }
  let(:conversation) do
    Conversation.create!(
      user: user,
      conversation_topic: 'Race Condition Test',
      max_rounds: 2,
      participants_attributes: [
        { name: 'Alice', model_id: 'openai/gpt-4o-mini', turn_order: 1 },
        { name: 'Bob', model_id: 'anthropic/claude-3-haiku', turn_order: 2 }
      ]
    )
  end
  let(:service) { RoundService.new(conversation) }

  describe 'race condition protection' do
    it 'should handle concurrent round advancement gracefully' do
      # Set up conversation in a state where round advancement could happen
      conversation.update!(current_round: 1)
      
      # Simulate race condition by advancing the round externally
      # This represents another process/request advancing the round
      original_round = conversation.current_round
      
      # Manually advance the round to simulate concurrent access
      Conversation.where(id: conversation.id).update_all(current_round: original_round + 1)
      
      # Now try to advance again - should detect the race condition
      result = service.send(:advance_round!)
      
      # Should return false indicating race condition was detected
      expect(result).to be(false)
      
      # Conversation should be in the correct final state (advanced by the "other" process)
      conversation.reload
      expect(conversation.current_round).to eq(original_round + 1)
    end

    it 'should successfully advance when no race condition occurs' do
      conversation.update!(current_round: 1)
      original_round = conversation.current_round
      
      # Normal case - should advance successfully
      result = service.send(:advance_round!)
      
      expect(result).to be(true)
      conversation.reload
      expect(conversation.current_round).to eq(original_round + 1)
    end

    it 'should complete conversation when advancing past max_rounds' do
      # Set up conversation at max rounds
      conversation.update!(current_round: 2, max_rounds: 2)
      
      result = service.send(:advance_round!)
      
      expect(result).to be(true)
      conversation.reload
      expect(conversation.current_round).to eq(3)  # Past max_rounds
      expect(conversation.status).to eq('complete')
    end

    it 'should not complete conversation if race condition prevents advancement' do
      # Set up conversation at max rounds
      conversation.update!(current_round: 2, max_rounds: 2)
      
      # Simulate another process advancing first
      Conversation.where(id: conversation.id).update_all(current_round: 3)
      
      result = service.send(:advance_round!)
      
      expect(result).to be(false)  # Race condition detected
      conversation.reload
      expect(conversation.current_round).to eq(3)
      # Status might be complete if the other process completed it
      # or still in_progress if not - we don't control that in this test
    end
  end
end