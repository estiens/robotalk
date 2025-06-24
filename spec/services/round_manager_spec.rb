require 'rails_helper'

RSpec.describe RoundManager, type: :service do
  let(:user) { User.create!(email: "test@example.com", password: "password123") }
  let(:conversation) { Conversation.create!(user: user, max_rounds: 3, conversation_topic: "Test Topic") }
  let(:round_manager) { RoundManager.new(conversation) }

  before do
    conversation.participants.create!(model_id: "openai/gpt-4", name: "Assistant 1", turn_order: 1)
    conversation.participants.create!(model_id: "anthropic/claude-3-haiku", name: "Assistant 2", turn_order: 2)
    conversation.participants.create!(model_id: "deepseek/deepseek-r1", name: "Assistant 3", turn_order: 3)
  end

  describe "conversation#current_round" do
    it "starts at 1 when no assistant messages exist" do
      expect(conversation.current_round).to eq(1)
    end

    it "stays at 1 for rounds 1-3 assistant messages" do
      participants = conversation.participants.ordered
      
      message1 = conversation.messages.create!(
        role: "assistant", 
        content: "Message", 
        model_id: participants[0].model_id,
        conversation_participant: participants[0]
      )
      conversation.reload
      expect(conversation.current_round).to eq(1)

      message2 = conversation.messages.create!(
        role: "assistant", 
        content: "Message", 
        model_id: participants[1].model_id,
        conversation_participant: participants[1]
      )
      conversation.reload
      expect(conversation.current_round).to eq(1)

      message3 = conversation.messages.create!(
        role: "assistant", 
        content: "Message", 
        model_id: participants[2].model_id,
        conversation_participant: participants[2]
      )
      conversation.reload
      expect(conversation.current_round).to eq(2)
    end

    it "advances to 2 after round 1 completes, then continues in round 2" do
      participants = conversation.participants.ordered
      4.times { |i|
        participant = participants[i % 3]
        conversation.messages.create!(
          role: "assistant", 
          content: "Message #{i+1}", 
          model_id: participant.model_id,
          conversation_participant: participant
        )
      }
      conversation.reload
      expect(conversation.current_round).to eq(2)
    end

    it "handles zero participants gracefully" do
      conversation.participants.destroy_all
      expect(conversation.current_round).to eq(1)
    end
  end

  describe "#next_speaker" do
    it "returns first participant when no assistant messages exist" do
      next_speaker = round_manager.next_speaker
      expect(next_speaker).to eq(conversation.participants.ordered.first)
      expect(next_speaker.turn_order).to eq(1)
    end

    it "returns second participant after first has spoken" do
      first_participant = conversation.participants.ordered.first
      conversation.messages.create!(
        role: "assistant", 
        content: "First message", 
        model_id: first_participant.model_id,
        conversation_participant: first_participant
      )

      next_speaker = round_manager.next_speaker
      expect(next_speaker.turn_order).to eq(2)
    end

    it "cycles back to first participant after last has spoken" do
      conversation.participants.ordered.each do |participant|
        conversation.messages.create!(
          role: "assistant", 
          content: "Message from #{participant.name}", 
          model_id: participant.model_id,
          conversation_participant: participant
        )
      end

      next_speaker = round_manager.next_speaker
      expect(next_speaker).to eq(conversation.participants.ordered.first)
      expect(next_speaker.turn_order).to eq(1)
    end

    it "returns nil if message has no conversation_participant" do
      conversation.messages.create!(role: "assistant", content: "Message", model_id: "unknown/model", conversation_participant: nil)
      expect(round_manager.next_speaker).to eq(conversation.participants.ordered.first)
    end
  end
end
