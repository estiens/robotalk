# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe 'Conversation Form', type: :system, vcr: true do

  it 'creates a conversation using dialogue type and character archetypes' do
    visit new_conversation_path

    # Should see the form with all the new sections
    expect(page).to have_css('[data-test="page-title"]', text: 'Create a New Conversation')
    expect(page).to have_css('h2', text: 'Dialogue Instructions')
    expect(page).to have_css('h2', text: 'AI Participants')

    # Enter conversation topic and max rounds first
    fill_in 'conversation_conversation_topic', with: 'Free Will vs Determinism'
    fill_in 'conversation_max_rounds', with: '5'

    # Manually set the dialogue instructions hidden field using JavaScript
    page.execute_script("document.querySelector('input[name=\"conversation[dialogue_instructions]\"]').value = 'Conduct a structured debate on the topic'")
    
    # Ensure we have the right number of participants
    expect(page).to have_css('[data-participant-form-target="container"] .participant-item', count: 2)

    # Fill in participant names (which are required)
    fill_in 'conversation[participants_attributes][0][name]', with: 'Participant 1'
    fill_in 'conversation[participants_attributes][1][name]', with: 'Participant 2'

    # Select models for participants
    select 'OpenAI: GPT-4o Mini', from: 'conversation[participants_attributes][0][model_id]'
    select 'Anthropic: Claude 3 Haiku', from: 'conversation[participants_attributes][1][model_id]'

    # Submit the form
    find('[data-test="create-conversation"]').click

    # Should be redirected to the conversation show page - use data attributes
    expect(page).to have_css('[data-test="conversation-topic"]', text: 'Free Will vs Determinism')
    expect(page).to have_css('[data-test="round-indicator"]', text: 'Ready to Begin')

    # Verify the conversation was created with correct data
    conversation = Conversation.last
    expect(conversation.conversation_topic).to eq('Free Will vs Determinism')
    expect(conversation.max_rounds).to eq(5)
    expect(conversation.participants.count).to eq(2)

    # Verify participant data exists
    expect(conversation.participants.count).to eq(2)
    expect(conversation.participants.first.model_id).to eq('openai/gpt-4o-mini')
    expect(conversation.participants.second.model_id).to eq('anthropic/claude-3-haiku')
  end

  it 'allows custom dialogue instructions' do
    visit new_conversation_path

    # Select custom dialogue type - keep existing selection
    expect(find('select[data-test="dialogue-type"]').value).to eq('custom')

    # Wait for custom dialogue instructions field to appear
    expect(page).to have_css('textarea[data-dialogue-form-target="dialogueInstructionsTextarea"]')

    # Enter custom dialogue instructions
    find('textarea[data-dialogue-form-target="dialogueInstructionsTextarea"]').fill_in with: 'Conduct a philosophical exploration of the meaning of life, asking deep questions and examining different perspectives.'

    # Wait for the JS to process and create participants
    expect(page).to have_css('[data-participant-form-target="container"] .participant-item', count: 2)

    # Fill in participant names and assign models
    fill_in 'conversation[participants_attributes][0][name]', with: 'Philosopher 1'
    select 'OpenAI: GPT-4o', from: 'conversation[participants_attributes][0][model_id]'

    fill_in 'conversation[participants_attributes][1][name]', with: 'Philosopher 2'
    select 'Anthropic: Claude 3.5 Sonnet', from: 'conversation[participants_attributes][1][model_id]'

    # Enter conversation topic
    fill_in 'conversation_conversation_topic', with: 'The Meaning of Life'

    # Set max rounds
    fill_in 'conversation_max_rounds', with: '3'

    # Submit the form
    find('[data-test="create-conversation"]').click

    # Wait for the redirect to complete - check for conversation page elements
    expect(page).to have_css('[data-test="conversation-topic"]', text: 'The Meaning of Life')
    expect(page).to have_css('[data-test="round-indicator"]', text: 'Ready to Begin')

    # Verify the conversation was created
    conversation = Conversation.last
    expect(conversation).to be_present
    expect(conversation.conversation_topic).to eq('The Meaning of Life')
  end

  it 'allows editing of premade template descriptions' do
    visit new_conversation_path

    # Select a dialogue type
    find('select[data-test="dialogue-type"]').select('Creative Brainstorm')

    # Wait for the template description to appear
    expect(page).to have_css('textarea[data-dialogue-form-target="dialogueInstructionsTextarea"]')

    # Edit the template description
    find('textarea[data-dialogue-form-target="dialogueInstructionsTextarea"]').fill_in with: 'Modified: Work together to brainstorm innovative solutions to climate change, focusing on practical and scalable approaches.'

    # The JS will create two participants
    expect(page).to have_css('[data-participant-form-target="container"] .participant-item', count: 2)

    # Fill in participant names and assign models
    fill_in 'conversation[participants_attributes][0][name]', with: 'Collaborator 1'
    select 'OpenAI: GPT-4o', from: 'conversation[participants_attributes][0][model_id]'

    fill_in 'conversation[participants_attributes][1][name]', with: 'Collaborator 2'
    select 'Anthropic: Claude 3.5 Sonnet', from: 'conversation[participants_attributes][1][model_id]'

    # Enter conversation topic
    fill_in 'conversation_conversation_topic', with: 'Climate Change Solutions'

    # Set max rounds
    fill_in 'conversation_max_rounds', with: '3'

    # Submit the form
    find('[data-test="create-conversation"]').click

    # Wait for the redirect to complete
    expect(page).to have_css('[data-test="conversation-topic"]', text: 'Climate Change Solutions')
    expect(page).to have_css('[data-test="round-indicator"]', text: 'Ready to Begin')

    # Verify the conversation was created
    conversation = Conversation.last
    expect(conversation).to be_present
    expect(conversation.conversation_topic).to eq('Climate Change Solutions')
  end

  it 'handles character archetype selection and clearing' do
    visit new_conversation_path

    # Select a dialogue type first
    find('select[data-test="dialogue-type"]').select('Friendly Discussion')
    expect(page).to have_css('textarea[data-dialogue-form-target="dialogueInstructionsTextarea"]')

    # The JS will create two participants
    expect(page).to have_css('[data-participant-form-target="container"] .participant-item', count: 2)

    # Enter conversation topic
    fill_in 'conversation_conversation_topic', with: 'Test Topic'

    # Set max rounds
    fill_in 'conversation_max_rounds', with: '3'

    # Fill in participant names and assign models
    fill_in 'conversation[participants_attributes][0][name]', with: 'Participant 1'
    select 'OpenAI: GPT-4o', from: 'conversation[participants_attributes][0][model_id]'

    fill_in 'conversation[participants_attributes][1][name]', with: 'Participant 2'
    select 'Anthropic: Claude 3.5 Sonnet', from: 'conversation[participants_attributes][1][model_id]'

    # Submit the form
    find('[data-test="create-conversation"]').click

    # Verify the conversation was created successfully
    expect(page).to have_css('[data-test="conversation-topic"]', text: 'Test Topic')
    expect(page).to have_css('[data-test="round-indicator"]', text: 'Ready to Begin')

    conversation = Conversation.last
    expect(conversation).to be_present
    expect(conversation.conversation_topic).to eq('Test Topic')
  end
end
