require 'rails_helper'

RSpec.describe Conversation, type: :model do
  let(:user) { User.create!(email: "test@example.com", password: "password123") }
  let(:conversation) { Conversation.create!(user: user, max_rounds: 3, conversation_topic: "Test Topic") }

  describe "round management" do
    before do
      # Create 3 participants
      conversation.participants.create!(
        model_id: "openai/gpt-4",
        name: "Assistant 1",
        turn_order: 1,
        character_prompt: "You are a helpful assistant"
      )
      conversation.participants.create!(
        model_id: "anthropic/claude-3-haiku",
        name: "Assistant 2",
        turn_order: 2,
        character_prompt: "You are a creative thinker"
      )
      conversation.participants.create!(
        model_id: "deepseek/deepseek-r1",
        name: "Assistant 3",
        turn_order: 3,
        character_prompt: "You are an analytical mind"
      )
    end

    describe "#current_round" do
      it "starts at 1 when no assistant messages exist" do
        expect(conversation.current_round).to eq(1)
      end

      it "stays at 1 until all participants speak, then advances to 2" do
        participants = conversation.participants.ordered
        
        conversation.messages.create!(role: "assistant", content: "Message", model_id: participants[0].model_id, conversation_participant: participants[0])
        expect(conversation.current_round).to eq(1)

        conversation.messages.create!(role: "assistant", content: "Message", model_id: participants[1].model_id, conversation_participant: participants[1])
        expect(conversation.current_round).to eq(1)

        conversation.messages.create!(role: "assistant", content: "Message", model_id: participants[2].model_id, conversation_participant: participants[2])
        conversation.reload
        expect(conversation.current_round).to eq(2)
      end

      it "advances to 2 after round 1 completes" do
        participants = conversation.participants.ordered
        4.times { |i|
          participant = participants[i % 3]
          conversation.messages.create!(role: "assistant", content: "Message #{i+1}", model_id: participant.model_id, conversation_participant: participant)
        }
        conversation.reload
        expect(conversation.current_round).to eq(2)
      end

      it "advances correctly with partial rounds" do
        # With 3 participants, after 4 messages we should be in round 2
        participants = conversation.participants.ordered
        4.times { |i|
          participant = participants[i % 3]
          conversation.messages.create!(role: "assistant", content: "Message", model_id: participant.model_id, conversation_participant: participant)
        }
        conversation.reload
        expect(conversation.current_round).to eq(2)
      end

      it "handles zero participants gracefully" do
        conversation.participants.destroy_all
        conversation.reload
        expect(conversation.current_round).to eq(1)
      end
    end

    describe "#can_continue?" do
      it "returns true when status is interactive and under max rounds" do
        conversation.update!(status: "interactive")
        expect(conversation.can_continue?).to be true
      end

      it "returns false when current round equals max rounds" do
        conversation.update!(status: "interactive", max_rounds: 1)
        3.times { |i|
          model = conversation.participants[i % 3].model_id
          conversation.messages.create!(role: "assistant", content: "Message", model_id: model)
        }
        expect(conversation.can_continue?).to be false
      end

      it "returns false when status is not interactive" do
        conversation.update!(status: "complete")
        expect(conversation.can_continue?).to be false
      end
    end

    describe "#next_speaker" do
      it "returns first participant when no assistant messages exist" do
        next_speaker = conversation.next_speaker
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

        next_speaker = conversation.next_speaker
        expect(next_speaker.turn_order).to eq(2)
      end

      it "cycles back to first participant after last has spoken" do
        # All participants speak once
        conversation.participants.ordered.each do |participant|
          conversation.messages.create!(
            role: "assistant",
            content: "Message from #{participant.name}",
            model_id: participant.model_id,
            conversation_participant: participant
          )
        end

        next_speaker = conversation.next_speaker
        expect(next_speaker).to eq(conversation.participants.ordered.first)
        expect(next_speaker.turn_order).to eq(1)
      end

      it "returns nil if message has no conversation_participant" do
        conversation.messages.create!(
          role: "assistant",
          content: "Message",
          model_id: "unknown/model",
          conversation_participant: nil
        )

        expect(conversation.next_speaker).to eq(conversation.participants.ordered.first)
      end
    end

    describe "#participant_for_model" do
      it "finds participant by model_id" do
        participant = conversation.participants.first
        found = conversation.participant_for_model(participant.model_id)
        expect(found).to eq(participant)
      end

      it "returns nil for unknown model_id" do
        expect(conversation.participant_for_model("unknown/model")).to be_nil
      end
    end

    describe "#can_start?" do
      it "returns true with 2+ participants and interactive status" do
        conversation.update!(status: "interactive")
        expect(conversation.can_start?).to be true
      end

      it "returns false with less than 2 participants" do
        conversation.participants.destroy_all
        conversation.participants.create!(model_id: "openai/gpt-4", turn_order: 1)
        expect(conversation.can_start?).to be false
      end

      it "returns false when not interactive" do
        conversation.update!(status: "generating")
        expect(conversation.can_start?).to be false
      end
    end

    describe "ConversationParticipant#has_spoken_in_round?" do
      let(:participant) { conversation.participants.first }

      it "returns false when participant hasn't spoken in the round" do
        expect(participant.has_spoken_in_round?(1)).to be false
      end

      it "returns true when participant has spoken in the round" do
        participant.messages.create!(
          conversation: conversation,
          role: "assistant",
          content: "Test message",
          round_number: 1
        )

        expect(participant.has_spoken_in_round?(1)).to be true
      end

      it "checks specific round numbers correctly" do
        participant.messages.create!(
          conversation: conversation,
          role: "assistant",
          content: "Round 1 message",
          round_number: 1
        )

        expect(participant.has_spoken_in_round?(1)).to be true
        expect(participant.has_spoken_in_round?(2)).to be false
      end
    end
  end

  describe "validations" do
    it "validates max_rounds numericality" do
      conversation = Conversation.new(user: user, conversation_topic: "Test", max_rounds: "not_a_number")
      expect(conversation).not_to be_valid
      expect(conversation.errors[:max_rounds]).to include("is not a number")
    end

    it "requires conversation_topic" do
      conversation = Conversation.new(user: user, max_rounds: 5)
      expect(conversation).not_to be_valid
      expect(conversation.errors[:conversation_topic]).to include("can't be blank")
    end

    it "validates max_rounds is between 1 and 50" do
      conversation.max_rounds = 0
      expect(conversation).not_to be_valid

      conversation.max_rounds = 51
      expect(conversation).not_to be_valid

      conversation.max_rounds = 25
      expect(conversation).to be_valid
    end
  end

  describe "defaults" do
    it "sets default status to interactive" do
      conv = Conversation.create!(user: user, max_rounds: 5, conversation_topic: "Test")
      expect(conv.status).to eq("interactive")
    end

    it "sets default dialogue_instructions" do
      conv = Conversation.create!(user: user, max_rounds: 5, conversation_topic: "Test")
      expect(conv.dialogue_instructions).to include("thoughtful conversation")
    end
  end
end
