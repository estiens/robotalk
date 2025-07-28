# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationParticipant do
  # Create a valid record for shoulda-matchers to use
  subject { create('conversation_participant') }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:model_id) }
    it { is_expected.to validate_uniqueness_of(:turn_order).scoped_to(:conversation_id) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:conversation) }
  end
end
