require 'rails_helper'
require 'ostruct'

RSpec.describe 'Semantic LLM Conversation', type: :system do
  before do
    models = [
      OpenStruct.new(id: 'google/gemini-2.0-flash-001', name: 'Google Gemini 2.0 Flash'),
      OpenStruct.new(id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini'),
      OpenStruct.new(id: 'anthropic/claude-3-5-sonnet', name: 'Claude 3.5 Sonnet')
    ]
    allow(RubyLLM::Models).to receive(:all).and_return(models)
  end

  it 'allows creating and running a full conversation', :vcr do
    visit new_conversation_path

    # Verify initial state
    expect(page).to have_css('.participant-item', count: 2)

    # Add and remove a participant
    click_on 'Add Participant'
    expect(page).to have_css('.participant-item', count: 3)
    within('[data-test="participant-2"]') do
      find('[data-test="remove-participant"]').click
    end
    expect(page).to have_css('.participant-item', count: 2)

    # Fill in conversation details
    find('[data-test="conversation-topic"]').fill_in with: 'AI Philosophy Debate'
    fill_in 'dialogue-instructions-textarea', with: 'Debate whether artificial intelligence can achieve true consciousness.'
    find('[data-test="max-rounds"]').fill_in with: '2'

    within('[data-test="participant-0"]') do
      fill_in 'Name', with: 'Skeptical Philosopher'
      select 'Google Gemini 2.0 Flash', from: 'AI Model'
      fill_in 'Character Description', with: 'A skeptical philosopher.'
    end

    within('[data-test="participant-1"]') do
      fill_in 'Name', with: 'Optimistic Researcher'
      select 'GPT-4o Mini', from: 'AI Model'
      fill_in 'Character Description', with: 'An optimistic AI researcher.'
    end

    find('[data-test="create-conversation"]').click

    # Wait for conversation to be created and started
    expect(page).to have_content('AI Philosophy Debate')
    VCR.use_cassette('conversation_golden_path_start') do
      find('[data-test="start-conversation-button"]').click
      expect(page).to have_content('Round 1/2', wait: 60)
    end

    # Enable auto-continue to progress the conversation
    find('[data-test="auto-continue-toggle"]').click

    # Wait for the conversation to progress
    VCR.use_cassette('conversation_golden_path_continue') do
      expect(page).to have_content('Round 2/2', wait: 60)
    end

    # The conversation should now be complete.
    expect(page).to have_css('[data-test="conversation-complete-message"]', wait: 30)
  end
end
