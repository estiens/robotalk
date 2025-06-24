require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'associations' do
    it { should belong_to(:conversation) }
    it { should have_many(:tool_calls).dependent(:destroy) }
    it { should belong_to(:conversation_participant).optional }
  end

  describe 'callbacks' do
    it 'triggers set_round_number before creation' do
      conversation = create(:conversation)
      message = build(:message, conversation: conversation)
      expect(message).to receive(:set_round_number)
      message.save!
    end
  end

  describe '#set_round_number' do
    let(:conversation) { create(:conversation, max_rounds: 5) }
    let!(:participant1) { create(:conversation_participant, conversation: conversation, turn_order: 1) }
    let!(:participant2) { create(:conversation_participant, conversation: conversation, turn_order: 2) }

    it 'assigns round 1 to the first message' do
      message = create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant1)
      expect(message.round_number).to eq(1)
    end

    it 'assigns round 1 to the second message in the same round' do
      create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant1)
      message2 = create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant2)
      expect(message2.round_number).to eq(1)
    end

    it 'assigns round 2 after all participants have spoken in round 1' do
      create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant1)
      create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant2)
      message3 = create(:message, conversation: conversation, role: 'assistant', conversation_participant: participant1)
      expect(message3.round_number).to eq(2)
    end

    it 'does not assign a round number to user messages' do
      message = create(:message, conversation: conversation, role: 'user')
      expect(message.round_number).to be_nil
    end
  end
end
