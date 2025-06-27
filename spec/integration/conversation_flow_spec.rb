require 'rails_helper'

RSpec.describe "Conversation Flow", type: :model do
  let(:user) { User.create!(email: "test@example.com", password: "password") }
  let(:conversation) do
    Conversation.create!(
      user: user,
      conversation_topic: "AI and the Future",
      max_rounds: 3,
      participants_attributes: [
        { name: "Alice", model_id: "openai/gpt-4o-mini", turn_order: 1 },
        { name: "Bob", model_id: "anthropic/claude-3-haiku", turn_order: 2 }
      ]
    )
  end

  let(:alice) { conversation.participants.find_by(name: "Alice") }
  let(:bob) { conversation.participants.find_by(name: "Bob") }

  describe "initial state" do
    it "starts with correct initial values" do
      expect(conversation.current_round).to eq(1)
      expect(conversation.status).to eq("pending")
      expect(conversation.messages.count).to eq(0)
      expect(conversation.can_start?).to be true
      expect(conversation.can_continue?).to be true
    end

    it "determines first speaker correctly" do
      expect(conversation.current_speaker).to eq(alice)
    end
  end

  describe "speaker order and round management" do
    before do
      # Mock LlmService to avoid actual API calls
      allow(LlmService).to receive(:new) do |conv, participant|
        double("LlmService", generate_response: create_mock_message_for(participant))
      end
    end

    def create_mock_message_for(participant)
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: participant,
        role: Message::ROLE_ASSISTANT,
        model_id: participant.model_id,
        round_number: conversation.current_round,
        content: "Mock response from #{participant.name}"
      )
    end

    it "follows correct speaker order within a round" do
      # Round 1: Alice speaks first
      expect(conversation.current_speaker).to eq(alice)
      expect(conversation.current_round).to eq(1)

      # Alice responds
      message1 = conversation.have_current_speaker_respond!
      expect(message1.conversation_participant).to eq(alice)
      expect(message1.round_number).to eq(1)

      # Should advance to Bob
      expect(conversation.current_speaker).to eq(bob)
      expect(conversation.current_round).to eq(1) # Still round 1

      # Bob responds
      message2 = conversation.have_current_speaker_respond!
      expect(message2.conversation_participant).to eq(bob)
      expect(message2.round_number).to eq(1)

      # Round should advance to 2, Alice speaks first again
      expect(conversation.current_round).to eq(2)
      expect(conversation.current_speaker).to eq(alice)
    end

    it "tracks round completion correctly" do
      expect(conversation.round_complete?).to be false

      # Alice speaks
      conversation.have_current_speaker_respond!
      expect(conversation.round_complete?).to be false
      expect(conversation.current_round).to eq(1)

      # Bob speaks - should complete round 1
      conversation.have_current_speaker_respond!
      expect(conversation.current_round).to eq(2)
    end

    it "completes conversation after max rounds" do
      # Complete 3 rounds (6 total messages)
      6.times { conversation.have_current_speaker_respond! }

      expect(conversation.current_round).to eq(4) # Past max_rounds
      expect(conversation.status).to eq("complete")
      expect(conversation.can_continue?).to be false
    end

    it "tracks has_spoken_in_round correctly" do
      expect(alice.has_spoken_in_round?(1)).to be false
      expect(bob.has_spoken_in_round?(1)).to be false

      # Alice speaks in round 1
      conversation.have_current_speaker_respond!
      expect(alice.has_spoken_in_round?(1)).to be true
      expect(bob.has_spoken_in_round?(1)).to be false

      # Bob speaks in round 1
      conversation.have_current_speaker_respond!
      expect(alice.has_spoken_in_round?(1)).to be true
      expect(bob.has_spoken_in_round?(1)).to be true

      # Now in round 2 - neither has spoken yet
      expect(alice.has_spoken_in_round?(2)).to be false
      expect(bob.has_spoken_in_round?(2)).to be false
    end
  end

  describe "message history" do
    before do
      # Create some test messages
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: alice,
        role: Message::ROLE_ASSISTANT,
        model_id: alice.model_id,
        round_number: 1,
        content: "Hello, I'm Alice!"
      )

      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: bob,
        role: Message::ROLE_ASSISTANT,
        model_id: bob.model_id,
        round_number: 1,
        content: "Nice to meet you Alice, I'm Bob!"
      )

      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: alice,
        role: Message::ROLE_ASSISTANT,
        model_id: alice.model_id,
        round_number: 2,
        content: "How are you doing today?"
      )
    end

    it "builds conversation history correctly" do
      history = conversation.conversation_history

      expect(history).to include("Alice: Hello, I'm Alice!")
      expect(history).to include("Bob: Nice to meet you Alice, I'm Bob!")
      expect(history).to include("Alice: How are you doing today?")

      # Should be in chronological order
      lines = history.split("\n\n")
      expect(lines[0]).to eq("Alice: Hello, I'm Alice!")
      expect(lines[1]).to eq("Bob: Nice to meet you Alice, I'm Bob!")
      expect(lines[2]).to eq("Alice: How are you doing today?")
    end

    it "respects history limit" do
      history = conversation.conversation_history(limit: 2)
      lines = history.split("\n\n")

      expect(lines.count).to eq(2)
      expect(lines[0]).to eq("Bob: Nice to meet you Alice, I'm Bob!")
      expect(lines[1]).to eq("Alice: How are you doing today?")
    end
  end

  describe "LlmService integration" do
    let(:mock_client) { double("OpenRouter::Client") }
    let(:mock_response) { { "choices" => [ { "message" => { "content" => "Test response content" } } ] } }

    before do
      allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:complete).and_return(mock_response)
    end

    it "sends correct messages to OpenRouter" do
      service = LlmService.new(conversation, alice)

      expect(OpenRouter::Client).to receive(:new)
      expect(mock_client).to receive(:complete).with(
        array_including(
          hash_including(role: "system", content: alice.system_prompt_with_topic),
          hash_including(role: "user", content: "Please introduce yourself and start discussing: AI and the Future")
        ),
        hash_including(model: "openai/gpt-4o-mini")
      )

      service.generate_response
    end

    it "includes conversation history in subsequent calls" do
      # Add a message to create history
      AssistantMessage.create!(
        conversation: conversation,
        conversation_participant: alice,
        role: Message::ROLE_ASSISTANT,
        model_id: alice.model_id,
        round_number: 1,
        content: "Previous message content"
      )

      service = LlmService.new(conversation, bob)

      expect(mock_client).to receive(:complete).with(
        array_including(
          hash_including(role: "assistant", content: "Previous message content", name: "Alice")
        ),
        anything
      )

      service.generate_response
    end

    it "creates AssistantMessage with correct attributes" do
      service = LlmService.new(conversation, alice)
      message = service.generate_response

      expect(message).to be_a(AssistantMessage)
      expect(message.conversation).to eq(conversation)
      expect(message.conversation_participant).to eq(alice)
      expect(message.role).to eq(Message::ROLE_ASSISTANT)
      expect(message.model_id).to eq(alice.model_id)
      expect(message.round_number).to eq(conversation.current_round)
      expect(message.content).to eq("Test response content")
    end
  end

  describe "error handling" do
    before do
      # Mock OpenRouter for this test
      allow(OpenRouter::Client).to receive(:new) do
        client = double("OpenRouter::Client")
        allow(client).to receive(:complete) do |messages, options|
          { "choices" => [ { "message" => { "content" => "Mock response" } } ] }
        end
        client
      end
    end

    it "handles missing current speaker gracefully" do
      # Use the actual have_current_speaker_respond! method which handles advancement
      6.times do |i|
        break unless conversation.current_speaker # Stop when no more speakers
        conversation.have_current_speaker_respond!
      end

      expect(conversation.current_speaker).to be_nil
      expect { conversation.have_current_speaker_respond! }.to raise_error("No current speaker available")
    end
  end

  describe "full conversation generation", :vcr do
    it "generates complete conversation automatically with real API calls" do
      VCR.use_cassette("conversation_flow/full_generation", record: :new_episodes) do
        conversation.generate_full_conversation!

        expect(conversation.status).to eq("complete")
        expect(conversation.current_round).to eq(4) # Past max_rounds of 3
        expect(conversation.messages.count).to eq(6) # 3 rounds × 2 participants

        # Verify message order
        messages = conversation.messages.order(:created_at)
        expect(messages[0].conversation_participant).to eq(alice) # Round 1
        expect(messages[1].conversation_participant).to eq(bob)   # Round 1
        expect(messages[2].conversation_participant).to eq(alice) # Round 2
        expect(messages[3].conversation_participant).to eq(bob)   # Round 2
        expect(messages[4].conversation_participant).to eq(alice) # Round 3
        expect(messages[5].conversation_participant).to eq(bob)   # Round 3

        # Verify actual content was generated
        messages.each do |message|
          expect(message.content).to be_present
          expect(message.content.length).to be > 10
        end
      end
    end
  end
end
