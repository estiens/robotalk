# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message do
  describe 'associations' do
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to have_many(:tool_calls).dependent(:destroy) }
    it { is_expected.to belong_to(:conversation_participant).optional }
  end

  describe 'callbacks' do
    it 'triggers set_initial_round_number_for_shell before creation' do
      conversation = create('conversation')
      message = build('message', conversation: conversation, role: 'assistant')
      expect(message).to receive(:set_initial_round_number_for_shell)
      message.save!
    end
  end

  describe '#set_initial_round_number_for_shell' do
    let(:conversation) { create('conversation', max_rounds: 5) }
    let!(:participant1) { create('conversation_participant', conversation: conversation, turn_order: 1) }
    let!(:participant2) { create('conversation_participant', conversation: conversation, turn_order: 2) }

    it 'assigns round 1 to the first message' do
      message = create('message', conversation: conversation, role: 'assistant', conversation_participant: participant1)
      expect(message.round_number).to eq(1)
    end

    it 'assigns round 1 to the second message in the same round' do
      create('message', conversation: conversation, role: 'assistant', conversation_participant: participant1)
      message2 = create('message', conversation: conversation, role: 'assistant',
                                   conversation_participant: participant2)
      expect(message2.round_number).to eq(1)
    end

    it 'assigns round number from conversation current_round' do
      # Advance conversation to round 2
      conversation.update!(current_round: 2)

      message = create('message', conversation: conversation, role: 'assistant', conversation_participant: participant1)
      expect(message.round_number).to eq(2)
    end

    it 'does not assign a round number to user messages' do
      message = create('message', conversation: conversation, role: 'user')
      expect(message.round_number).to be_nil
    end
  end
end
