# frozen_string_literal: true

require 'rails_helper'

# This spec demonstrates JavaScript functionality for confirmation dialogs
RSpec.describe 'Conversation deletion with JavaScript confirmation', :js do
  around do |example|
    pending('PENDING: JS confirmation dialogs not working with Cuprite')
    example.run
  end

  let!(:user) { User.find_or_create_by(email: 'anonymous@roboconvo.local') { |u| u.password = 'password' } }

  describe 'with JavaScript enabled' do
    it 'shows confirmation dialog and deletes on accept' do
      conversation = create_test_conversation(user: user, topic: 'Test Topic for JS')

      visit conversations_path

      # Verify conversation exists
      expect(page).to have_content('Test Topic for JS')
      expect_record_to_exist(Conversation, conversation.id)

      # Accept confirmation and delete
      accept_confirmation_and_click('delete-conversation-button')

      # Verify deletion
      expect(page).to have_no_content('Test Topic for JS')
      expect_record_not_to_exist(Conversation, conversation.id)
    end

    it 'shows confirmation dialog and cancels on dismiss' do
      conversation = create_test_conversation(user: user, topic: 'Test Topic for JS Cancel')

      visit conversations_path

      # Verify conversation exists
      expect(page).to have_content('Test Topic for JS Cancel')
      expect_record_to_exist(Conversation, conversation.id)

      # Dismiss confirmation dialog
      dismiss_confirmation_and_click('delete-conversation-button')

      # Verify conversation still exists
      expect(page).to have_content('Test Topic for JS Cancel')
      expect_record_to_exist(Conversation, conversation.id)
    end
  end

  describe 'hover behavior for delete button' do
    it 'reveals delete button on hover', :js do
      conversation = create_test_conversation(user: user, topic: 'Hover Test Topic')

      visit conversations_path

      within_conversation_card(conversation.id) do
        # Delete button should be hidden initially
        expect(page).to have_test_element('delete-conversation-button', visible: false)

        # Hover over the card to reveal delete button
        page.find("[data-test='conversation-card-#{conversation.id}']").hover

        # Delete button should become visible
        expect(page).to have_test_element('delete-conversation-button', visible: true)
      end
    end
  end

  describe 'multiple conversation selection' do
    it 'can delete multiple conversations in sequence' do
      create_test_conversation(user: user, topic: 'First Topic')
      create_test_conversation(user: user, topic: 'Second Topic')
      create_test_conversation(user: user, topic: 'Third Topic')

      visit conversations_path

      # All conversations should be visible
      expect(page).to have_content('First Topic')
      expect(page).to have_content('Second Topic')
      expect(page).to have_content('Third Topic')

      initial_count = Conversation.count

      # Delete first conversation
      accept_confirmation_and_click('delete-conversation-button') # Will click first one found

      # Verify first deletion
      expect(Conversation.count).to eq(initial_count - 1)

      # Delete another conversation
      accept_confirmation_and_click('delete-conversation-button')

      # Verify second deletion
      expect(Conversation.count).to eq(initial_count - 2)
    end
  end
end
