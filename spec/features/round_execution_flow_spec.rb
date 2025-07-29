# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Round Execution Flow', type: :system do
  include CapybaraHelpers

  let!(:user) { User.find_or_create_by(email: 'anonymous@roboconvo.local') { |u| u.password = 'password' } }

  describe 'conversation show page' do
    it 'displays conversation details successfully', :js do
      # Create conversation using helper method
      conversation = create_test_conversation(user: user, topic: 'Test Discussion Topic')
      
      # Visit conversations index first to establish session
      sign_in_as_anonymous
      
      # Then navigate to specific conversation
      visit conversation_path(conversation)
      
      # Use data-test attributes for reliable assertions
      expect(page).to have_css('[data-test="conversation-topic"]', text: 'Test Discussion Topic')
      expect(page).to have_css('[data-test="round-indicator"]')
    end
  end

  describe 'basic conversation flow' do  
    it 'shows conversation with participants', :js do
      # Create conversation with proper participant setup
      conversation = create(:conversation, :with_alice_and_bob, 
        user: user, 
        conversation_topic: 'AI Discussion',
        max_rounds: 2
      )
      
      # Establish session first
      sign_in_as_anonymous
      
      # Visit the conversation
      visit conversation_path(conversation)
      
      # Verify conversation details using data attributes
      expect(page).to have_css('[data-test="conversation-topic"]', text: 'AI Discussion')
      expect(page).to have_content('Alice')
      expect(page).to have_content('Bob')
      expect(page).to have_css('[data-test="round-indicator"]')
    end
  end

  describe 'round execution' do
    it 'can start a conversation and track round progression', :vcr do
      # Skip if no API keys available for testing
      skip 'No API key available for testing' if ENV['OPENROUTER_API_KEY'].blank?
      
      # Create conversation with real models for testing
      conversation = Conversation.create!(
        user: user,
        conversation_topic: 'Brief discussion about creativity',
        dialogue_instructions: 'Have a short, friendly exchange about creativity.',
        max_rounds: 2,
        participants_attributes: [
          {
            model_id: 'openai/gpt-4o-mini',
            turn_order: 1,
            name: 'Creative Bot'
          },
          {
            model_id: 'anthropic/claude-3-haiku',
            turn_order: 2, 
            name: 'Analysis Bot'
          }
        ]
      )

      # Establish session
      sign_in_as_anonymous
      
      # Visit conversation
      visit conversation_path(conversation)

      # Should see initial state
      wait_for_test_element('conversation-topic')
      expect(page).to have_css('[data-test="conversation-topic"]', text: 'Brief discussion about creativity')
      expect(page).to have_css('[data-test="round-indicator"]', text: 'Ready to Begin')

      # Start the conversation 
      wait_for_test_element('continue-conversation-button')
      click_test_element('continue-conversation-button')

      # Wait for first round to complete
      wait_for_round_indicator

      # Verify we progressed to round 1
      expect(page).to have_css('[data-test="round-indicator"]', text: /Round 1/)

      # Continue to round 2
      wait_for_test_element('continue-conversation-button', timeout: CapybaraHelpers::LONG_TIMEOUT)
      click_test_element('continue-conversation-button')

      # Wait for second round 
      wait_for_round_indicator

      # Verify round progression and conversation completion
      conversation.reload
      expect(conversation.rounds.count).to be >= 2
      expect(conversation.messages.count).to be >= 2
    end
  end
end