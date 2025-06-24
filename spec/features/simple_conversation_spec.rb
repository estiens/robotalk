require 'rails_helper'
require 'ostruct'

RSpec.describe 'Simple Conversation Flow', type: :system do
  before do
    # Stub the call to RubyLLM::Models.all to prevent live API calls
    models_payload = [
      { id: 'openai/gpt-4o-mini', name: 'OpenAI: GPT-4o Mini' },
      { id: 'anthropic/claude-3-haiku', name: 'Anthropic: Claude 3 Haiku' }
    ].map { |h| OpenStruct.new(h) }

    allow(RubyLLM::Models).to receive(:all).and_return(models_payload)
  end

  it 'allows creating a basic conversation', :vcr do
    visit new_conversation_path

    # Fill in basic conversation details
    fill_in 'conversation_conversation_topic', with: 'Test Conversation'
    fill_in 'conversation_max_rounds', with: '2'

    # Add participants
    fill_in 'conversation[participants_attributes][0][name]', with: 'Assistant 1'
    select 'OpenAI: GPT-4o Mini', from: 'conversation[participants_attributes][0][model_id]'

    fill_in 'conversation[participants_attributes][1][name]', with: 'Assistant 2'
    select 'Anthropic: Claude 3 Haiku', from: 'conversation[participants_attributes][1][model_id]'

    # Submit the form
    find('[data-test="create-conversation"]').click

    # Should be redirected to the conversation show page
    expect(page).to have_css('[data-test="conversation-topic"]', text: 'Test Conversation')
    expect(page).to have_css('[data-test="round-indicator"]', text: 'Round 0/2')

    # Verify the conversation was created
    conversation = Conversation.last
    expect(conversation.conversation_topic).to eq('Test Conversation')
    expect(conversation.max_rounds).to eq(2)
    expect(conversation.participants.count).to eq(2)
  end
end
