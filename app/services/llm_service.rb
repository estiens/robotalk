# frozen_string_literal: true

class LlmService
  # Custom error classes
  class LlmApiError < StandardError; end
  class RateLimitError < LlmApiError; end
  
  attr_reader :conversation, :participant

  def initialize(conversation, participant)
    raise 'OpenRouter API key not configured' if ENV.fetch('OPENROUTER_API_KEY', nil).blank?

    @conversation = conversation
    @participant = participant
  end

  def generate_response
    Rails.logger.info "[LlmService] Generating response for #{participant.name}"

    # Build message array for OpenRouter API
    messages = build_messages

    Rails.logger.info "[LlmService] Sending #{messages.count} messages to #{participant.model_id}"

    # Use OpenRouter client directly
    client = OpenRouter::Client.new
    response = client.complete(
      messages,
      model: [participant.model_id], # OpenRouter expects model as array
      extras: {
        # Optional parameters can be added here
        # max_tokens: 1000,
        # temperature: 0.7
      }
    )

    # Extract content from response
    content = extract_content_from_response(response)

    # Return message data instead of creating the record
    # TurnService will handle the actual creation and round association
    {
      conversation_participant: participant,
      model_id: participant.model_id,
      content: content,
      metadata: {
        model_name: participant.model_id,
        response_metadata: response.to_h.slice('usage', 'model', 'created')
      }
    }
  rescue StandardError => e
    Rails.logger.error "[LlmService] Error: #{e.message}"

    # Return error data instead of creating the record
    # TurnService will handle creation and error propagation
    {
      conversation_participant: participant,
      model_id: participant.model_id,
      content: 'Sorry, I encountered an error generating my response.',
      metadata: { error: e.message, is_error: true }
    }
  end

  private

  def build_messages
    messages = []

    # Add system message with participant's full prompt
    messages << {
      role: 'system',
      content: participant.system_prompt_with_topic
    }

    # Add conversation history from all rounds as individual messages
    Message.joins(round: :conversation)
           .where(rounds: { conversation_id: conversation.id })
           .includes(:conversation_participant)
           .order(:created_at)
           .last(10) # Limit for context window
           .each do |msg|
      messages << {
        role: 'assistant',
        content: msg.content,
        name: msg.conversation_participant.name.gsub(/[^\w-]/, '_') # Sanitize name for OpenRouter API
      }
    end

    # Add user message to prompt next response
    messages << {
      role: 'user',
      content: build_user_message
    }

    messages
  end

  def build_user_message
    # Check if there are any messages in the conversation across all rounds
    has_messages = Message.joins(round: :conversation)
                          .where(rounds: { conversation_id: conversation.id })
                          .exists?
    
    if has_messages
      "Please continue the discussion about: #{conversation.conversation_topic}. Stay true to your character and respond naturally."
    else
      "Please introduce yourself and start discussing: #{conversation.conversation_topic}"
    end
  end

  def extract_content_from_response(response)
    # Handle different response formats from OpenRouter
    if response.is_a?(Hash)
      # Standard OpenAI-style response
      response.dig('choices', 0, 'message', 'content') ||
        response.dig('message', 'content') ||
        response['content'] ||
        'No content in response'
    elsif response.respond_to?(:content)
      response.content
    else
      response.to_s
    end
  end
end
