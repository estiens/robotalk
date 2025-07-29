# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Message do
  let(:conversation) { create(:conversation, :with_participants, participants_count: 2) }
  let(:round) { create(:round, conversation: conversation) }
  let(:participant) { conversation.participants.first }

  describe 'associations' do
    it { is_expected.to belong_to(:round) }
    it { is_expected.to belong_to(:conversation_participant).optional }
  end

  describe 'delegations' do
    it 'delegates conversation to round' do
      message = create(:message, round: round, conversation_participant: participant)
      expect(message.conversation).to eq(conversation)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:content) }
    
    context 'when message is streaming' do
      it 'does not require content' do
        message = build(:message, round: round, content: '', metadata: { 'status' => 'streaming' })
        expect(message).to be_valid
      end
    end
  end

  describe 'callbacks' do
    it 'triggers set_defaults before validation' do
      message = build(:message, round: round, conversation_participant: participant)
      expect(message).to receive(:set_defaults).and_call_original
      message.save!
    end

    it 'sets role to assistant by default' do
      message = create(:message, round: round, conversation_participant: participant, role: nil)
      expect(message.role).to eq('assistant')
    end
  end

  describe '#metadata' do
    it 'returns empty hash for nil metadata' do
      message = build(:message, round: round, metadata: nil)
      expect(message.metadata).to eq({})
    end

    it 'returns the metadata hash when present' do
      metadata = { 'model_name' => 'gpt-4', 'tokens' => 100 }
      message = build(:message, round: round, metadata: metadata)
      expect(message.metadata).to eq(metadata)
    end
  end

  describe '#metadata_value' do
    let(:message) { build(:message, round: round, metadata: { 'status' => 'completed', 'tokens' => 150 }) }

    it 'returns the value for existing keys' do
      expect(message.metadata_value('status')).to eq('completed')
      expect(message.metadata_value(:tokens)).to eq(150)
    end

    it 'returns nil for non-existing keys' do
      expect(message.metadata_value('non_existing')).to be_nil
    end

    it 'returns default value for non-existing keys' do
      expect(message.metadata_value('non_existing', 'default')).to eq('default')
    end
  end

  describe '#error_message?' do
    it 'returns true when is_error metadata is true' do
      message = build(:message, round: round, metadata: { 'is_error' => true })
      expect(message.error_message?).to be true
    end

    it 'returns false when is_error metadata is false' do
      message = build(:message, round: round, metadata: { 'is_error' => false })
      expect(message.error_message?).to be false
    end

    it 'returns false when is_error metadata is not present' do
      message = build(:message, round: round, metadata: {})
      expect(message.error_message?).to be false
    end
  end

  describe '#streaming_message?' do
    it 'returns true when status metadata is streaming' do
      message = build(:message, round: round, metadata: { 'status' => 'streaming' })
      expect(message.streaming_message?).to be true
    end

    it 'returns false when status metadata is not streaming' do
      message = build(:message, round: round, metadata: { 'status' => 'completed' })
      expect(message.streaming_message?).to be false
    end

    it 'returns false when status metadata is not present' do
      message = build(:message, round: round, metadata: {})
      expect(message.streaming_message?).to be false
    end
  end
end
