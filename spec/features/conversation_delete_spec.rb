require 'rails_helper'

RSpec.describe "Conversation deletion", type: :feature do
  let!(:user) { User.find_or_create_by(email: "anonymous@roboconvo.local") { |u| u.password = "password" } }

  describe "on the index page" do
    it "has delete buttons that can be clicked" do
      conversation1 = create_test_conversation(user: user, topic: "Test Topic 1")
      conversation2 = create_test_conversation(user: user, topic: "Test Topic 2")

      visit conversations_path

      # Both conversations should be visible initially
      expect(page).to have_content("Test Topic 1")
      expect(page).to have_content("Test Topic 2")

      # Find the delete buttons using helpers
      within_conversation_card(conversation1.id) do
        expect(has_test_element?("delete-conversation-button", visible: false)).to be true
      end

      within_conversation_card(conversation2.id) do
        expect(has_test_element?("delete-conversation-button", visible: false)).to be true
      end
    end

    it "deletes conversation and all associated data when delete button is clicked" do
      conversation1 = create_test_conversation(user: user, topic: "Test Topic 1")
      conversation2 = create_test_conversation(user: user, topic: "Test Topic 2")
      message1 = create(:message, conversation: conversation1, content: "Test message 1")
      message2 = create(:message, conversation: conversation1, content: "Test message 2")

      visit conversations_path

      # Verify initial state - both conversations exist
      expect(page).to have_content("Test Topic 1")
      expect(page).to have_content("Test Topic 2")
      expect_record_to_exist(Conversation, conversation1.id)
      expect(Message.where(conversation: conversation1).count).to eq(2)

      # Record initial counts
      initial_conversation_count = Conversation.count
      initial_message_count = Message.count

      # Click the delete button for conversation1 using helper
      click_conversation_delete(conversation1.id)

      # Verify frontend changes - conversation1 is removed from page
      expect(page).not_to have_content("Test Topic 1")
      expect(page).to have_content("Test Topic 2")  # conversation2 should still be visible

      # Verify backend changes using helper methods
      expect_record_not_to_exist(Conversation, conversation1.id)
      expect_record_to_exist(Conversation, conversation2.id)
      expect(Conversation.count).to eq(initial_conversation_count - 1)
      expect(Message.where(conversation_id: conversation1.id).count).to eq(0)  # Messages should be deleted via cascade
      expect(Message.count).to eq(initial_message_count - 2)  # 2 messages belonged to conversation1

      # Verify we're still on the conversations index page
      expect(page).to have_current_path(conversations_path)
    end

    it "only deletes the selected conversation, leaving others intact" do
      conversation1 = create_test_conversation(user: user, topic: "Test Topic 1")
      conversation2 = create_test_conversation(user: user, topic: "Test Topic 2")

      visit conversations_path

      # Verify both conversations exist initially
      initial_count = Conversation.count
      expect(page).to have_content("Test Topic 1")
      expect(page).to have_content("Test Topic 2")

      # Delete conversation2 using helper
      click_conversation_delete(conversation2.id)

      # Verify only conversation2 is deleted using helpers
      expect_record_to_exist(Conversation, conversation1.id)
      expect_record_not_to_exist(Conversation, conversation2.id)
      expect(Conversation.count).to eq(initial_count - 1)

      # Verify UI updates correctly
      expect(page).to have_content("Test Topic 1")
      expect(page).not_to have_content("Test Topic 2")
    end

    it "reduces the conversation count by 1 when a conversation is deleted" do
      conversation1 = create_test_conversation(user: user, topic: "Test Topic 1")
      conversation2 = create_test_conversation(user: user, topic: "Test Topic 2")

      visit conversations_path

      # Record initial count
      initial_count = Conversation.count
      expect(initial_count).to eq(2)

      # Delete one conversation using helper
      click_conversation_delete(conversation1.id)

      # Count should be reduced by 1
      expect(Conversation.count).to eq(initial_count - 1)

      # Specific conversation should no longer exist
      expect_record_not_to_exist(Conversation, conversation1.id)
    end
  end
end
