require 'rails_helper'

RSpec.describe 'LLM Conversation', type: :feature do
  include CapybaraHelpers
  before do
    allow(RubyLLM::Models).to receive(:all).and_return([
      double(id: 'google/gemini-2.0-flash-001', name: 'Google Gemini 2.0 Flash', provider: 'Google'),
      double(id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini', provider: 'OpenAI')
    ])
  end

  xit 'creates and runs a conversation between two LLMs - PENDING: investigate streaming/content issues', vcr: true, js: true, slow: true do
    # Skip if no API key for recording
    skip "No API key available for recording" unless ENV['OPENROUTER_API_KEY'].present?

    user = User.find_or_create_by(email: "anonymous@roboconvo.local") { |u| u.password = SecureRandom.hex(16) }
    conversation = Conversation.create!(
      user: user,
      conversation_topic: 'Discuss the future of AI',
      dialogue_instructions: 'Engage in a thoughtful discussion about the future of AI.',
      max_rounds: 2,
      participants_attributes: [
        {
          model_id: 'google/gemini-2.0-flash-001',
          turn_order: 1,
          name: 'Assistant 1'
        },
        {
          model_id: 'openai/gpt-4o-mini',
          turn_order: 2,
          name: 'Assistant 2'
        }
      ]
    )

    visit conversation_path(conversation)

    # Should see the topic clearly displayed using helper
    wait_for_test_element("conversation-topic")

    # Start the conversation using helper
    wait_for_test_element("start-conversation-button", timeout: QUICK_TIMEOUT)
    click_test_element("start-conversation-button")

    # Wait for the conversation to start using helper
    wait_for_round_indicator

    # Wait for continue button after first message and click it
    wait_for_test_element("continue-conversation-button", timeout: LONG_TIMEOUT)
    click_test_element("continue-conversation-button")

    # Verify conversation progressed
    wait_for_round_indicator

    # Verify we have meaningful conversation content
    conversation.reload
    assistant_messages = conversation.messages.where(role: 'assistant')
    expect(assistant_messages.count).to be >= 2

    # Check that responses are substantial
    assistant_messages.each do |message|
      expect(message.content.length).to be > 10
      expect(message.content).to be_present
      expect(message.model_id).to be_present
    end
  end
end
