# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message do
  describe 'associations' do
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to belong_to(:conversation_participant).optional }
  end

  describe 'callbacks' do
    it 'triggers set_defaults before validation' do
      conversation = create('conversation')
      message = build('message', conversation: conversation, role: 'assistant')
      expect(message).to receive(:set_defaults).and_call_original
      message.save!
    end
  end

  describe '#set_defaults' do
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

    it 'assigns a round number even to user messages in current implementation' do
      message = create('message', conversation: conversation, role: 'user')
      # In current implementation, all messages get round_number assigned
      expect(message.round_number).to eq(1)
    end
  end
end
