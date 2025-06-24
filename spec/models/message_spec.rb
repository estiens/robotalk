require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'associations' do
    it { should belong_to(:conversation) }
    it { should have_many(:tool_calls).dependent(:destroy) }
  end

  describe 'creation' do
    it 'can be created with valid attributes' do
      conversation = create(:conversation)
      message = build(:message, conversation: conversation)
      expect(message).to be_valid
    end
  end
end
