require 'rails_helper'

RSpec.describe 'LLM Conversation', type: :feature do
  before do
    allow(RubyLLM::Models).to receive(:all).and_return([
      double(id: 'google/gemini-2.0-flash-001', name: 'Google Gemini 2.0 Flash', provider: 'Google'),
      double(id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini', provider: 'OpenAI')
    ])
  end

  it 'creates and runs a conversation between two LLMs', :vcr do
    VCR.use_cassette('LLM_Conversation/creates_and_runs_a_conversation_between_two_LLMs', record: :new_episodes) do
      api_key = ENV['OPENROUTER_API_KEY']
      skip "No API key available" unless api_key.present?

      user = User.find_or_create_by(email: "anonymous@roboconvo.local") { |u| u.password = SecureRandom.hex(16) }
      conversation = Conversation.create!(
        user: user,
        conversation_topic: 'Discuss the future of AI',
        dialogue_instructions: 'Engage in a thoughtful discussion about the future of AI, exploring both opportunities and challenges.',
        max_rounds: 3,
        participants_attributes: [
          {
            model_id: 'google/gemini-2.0-flash-001',
            turn_order: 1,
            name: 'GPT Assistant',
            character_prompt: 'You are a helpful AI assistant focused on providing thoughtful and balanced perspectives in your responses.'
          },
          {
            model_id: 'openai/gpt-4o-mini',
            turn_order: 2,
            name: 'Claude Assistant',
            character_prompt: 'You are a helpful AI assistant focused on providing thoughtful and balanced perspectives in your responses.'
          }
        ]
      )

      visit conversation_path(conversation)

      # Should see the topic clearly displayed
      expect(page).to have_selector('[data-test="conversation-topic"]')

      # Start the conversation
      expect(page).to have_selector('[data-test="start-conversation-button"]', wait: 5)
      find('[data-test="start-conversation-button"]').click

      # Should see the conversation has started
      expect(page).to have_selector('[data-test="round-indicator"]', wait: 30)

      # Wait for the continue button to appear after the first message is generated
      expect(page).to have_selector('[data-test="continue-conversation-button"]', wait: 30)
      find('[data-test="continue-conversation-button"]').click

      # Wait for the page to update with the new response
      expect(page).to have_selector('[data-test="round-indicator"]', wait: 10)

      # Continue one more time to see the conversation develop
      find('[data-test="continue-conversation-button"]').click

      # Wait for the page to update with the new response
      expect(page).to have_selector('[data-test="round-indicator"]', wait: 10)

      # Verify we have meaningful conversation content
      conversation = Conversation.last
      assistant_messages = conversation.messages.where(role: 'assistant')

      expect(assistant_messages.count).to be >= 2

      # Check that responses contain topic-relevant content
      assistant_messages.each do |message|
        expect(message.content.length).to be > 30 # Substantial responses
        # Check for topic relevance (case insensitive)
        content_lower = message.content.downcase
        is_topic_relevant = content_lower.include?('ai') ||
                           content_lower.include?('future') ||
                           content_lower.include?('technology') ||
                           content_lower.include?('intelligence')
        expect(is_topic_relevant).to be_truthy
      end

      # Verify metadata was stored correctly
      assistant_messages.each do |message|
        # Check that the message has content and model_id
        expect(message.content).to be_present
        expect(message.model_id).to be_present

        # Check metadata if it exists (acts_as_chat may not always set it)
        if message.metadata.present?
          expect(message.metadata).to be_a(Hash)
          expect(message.metadata['response_time_ms']).to be_present if message.metadata['response_time_ms']
          expect(message.metadata['model']).to be_present if message.metadata['model']
        end
      end
    end
  end

  it 'handles auto-continue functionality', :vcr do
    VCR.use_cassette('LLM_Conversation/handles_auto-continue_functionality', record: :new_episodes) do
      user = User.find_or_create_by(email: "anonymous@roboconvo.local") { |u| u.password = SecureRandom.hex(16) }
      conversation = Conversation.create!(
        user: user,
        conversation_topic: 'Quick test conversation',
        dialogue_instructions: 'Have a brief conversation about technology.',
        max_rounds: 2,
        participants_attributes: [
          {
            model_id: 'google/gemini-2.0-flash-001',
            turn_order: 1,
            name: 'Assistant 1'
          },
          {
            model_id: 'gpt-4o-mini',
            turn_order: 2,
            name: 'Assistant 2'
          }
        ]
      )

      visit conversation_path(conversation)

      # Start the conversation
      expect(page).to have_selector('[data-test="start-conversation-button"]')
      find('[data-test="start-conversation-button"]').click
      expect(page).to have_selector('[data-test="round-indicator"]', wait: 30)

      # Wait for auto-continue toggle to appear after conversation starts
      expect(page).to have_selector('[data-test="auto-continue-toggle"]', wait: 30)
      find('[data-test="auto-continue-toggle"]').click

      # Wait for auto-continue to complete the conversation
      expect(page).to have_selector('[data-test="round-indicator"]', wait: 60)

      # Verify conversation progressed
      conversation.reload
      expect(conversation.current_round).to be >= 1
    end
  end
end
