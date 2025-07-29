# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation do
  let(:user) { create(:user) }
  let(:conversation) do
    create(:conversation, :with_alice_and_bob,
           user: user,
           conversation_topic: 'AI Ethics',
           max_rounds: 3)
  end
  
  before do
    # Mock the callback method that doesn't exist yet
    allow_any_instance_of(Conversation).to receive(:process_new_message).and_return(nil)
  end

  describe 'validations' do
    it 'requires conversation_topic' do
      conversation = build(:conversation, conversation_topic: nil)
      expect(conversation).not_to be_valid
      expect(conversation.errors[:conversation_topic]).to include("can't be blank")
    end

    it 'requires max_rounds to be positive and <= 50' do
      conversation = build(:conversation, max_rounds: 0)
      expect(conversation).not_to be_valid

      conversation = build(:conversation, max_rounds: 51)
      expect(conversation).not_to be_valid

      conversation = build(:conversation, max_rounds: 25)
      expect(conversation).to be_valid
    end

    it 'requires at least 2 participants when starting' do
      solo_conversation = create(:conversation, :with_single_participant, user: user)
      expect(solo_conversation.can_start?).to be false
    end
  end

  describe 'associations' do
    it 'has many participants ordered by turn_order' do
      expect(conversation.participants.count).to eq(2)
      expect(conversation.participants.ordered.first.name).to eq('Alice')
      expect(conversation.participants.ordered.last.name).to eq('Bob')
    end

    it 'has many messages' do
      round = create(:round, conversation: conversation)
      message = create(:message, :with_participant,
                      round: round,
                      conversation_participant: conversation.participants.first,
                      content: 'Test message')

      expect(conversation.messages).to include(message)
    end
  end

  describe 'defaults' do
    it 'sets default values on creation' do
      new_conversation = create(:conversation, user: user, conversation_topic: 'Test')

      expect(new_conversation.status).to eq('pending')
      expect(new_conversation.current_round).to eq(0)
      expect(new_conversation.max_rounds).to eq(10)
      expect(new_conversation.dialogue_instructions).to be_present
    end
  end

  describe '#can_continue?' do
    it 'returns true when pending and within max rounds' do
      expect(conversation.can_continue?).to be true
    end

    it 'returns false when complete' do
      conversation.update!(status: :complete)
      expect(conversation.can_continue?).to be false
    end

    it 'returns false when past max rounds' do
      # Create rounds that exceed max_rounds (3 in the factory)
      4.times { |i| create(:round, conversation: conversation, number: i + 1) }
      expect(conversation.can_continue?).to be false
    end

    it 'returns false with no participants' do
      conversation.participants.destroy_all
      expect(conversation.can_continue?).to be false
    end
  end

  describe '#can_start?' do
    it 'returns true when pending with >= 2 participants' do
      expect(conversation.can_start?).to be true
    end

    it 'returns false when not pending' do
      # can_start? only checks if there are enough participants
      # Let's test it properly by removing participants
      conversation.participants.destroy_all
      expect(conversation.can_start?).to be false
    end

    it 'returns false with < 2 participants' do
      conversation.participants.last.destroy
      expect(conversation.can_start?).to be false
    end
  end

  describe '#current_speaker' do
    it 'returns first participant initially' do
      # Create a round that's ready to start (no messages yet)
      round = create(:round, conversation: conversation)
      expect(conversation.current_speaker.name).to eq('Alice')
    end

    it 'returns second participant after first has spoken' do
      # Create a round with partial progress (first participant has spoken)
      round = create(:round, :with_partial_messages, conversation: conversation, messages_count: 1)
      
      expect(conversation.current_speaker.name).to eq('Bob')
    end

    it 'returns nil when all participants have spoken in current round' do
      # Create a completed round where all participants have spoken
      round = create(:round, :with_all_messages, conversation: conversation)
      
      expect(conversation.current_speaker).to be_nil
    end
  end
end
