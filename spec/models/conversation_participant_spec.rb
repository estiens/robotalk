require 'rails_helper'

RSpec.describe ConversationParticipant, type: :model do
  # Create a valid record for shoulda-matchers to use
  subject { create(:conversation_participant) }

  describe 'validations' do
    it { should validate_presence_of(:model_id) }
    it { should validate_uniqueness_of(:turn_order).scoped_to(:conversation_id) }
  end

  describe 'associations' do
    it { should belong_to(:conversation) }
  end
end
