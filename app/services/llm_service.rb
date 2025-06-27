
class LlmService
  attr_reader :conversation, :participant

  def initialize(conversation, participant)
    @conversation = conversation
    @participant = participant
  end

  def generate_response
    Rails.logger.info "[LlmService] Generating response for #{participant.name} in round #{conversation.current_round}"

    # Build message array for OpenRouter API
    messages = build_messages

    Rails.logger.info "[LlmService] Sending #{messages.count} messages to #{participant.model_id}"

    # Use OpenRouter client directly
    begin
      client = OpenRouter::Client.new
    rescue NameError => e
      Rails.logger.error "[LlmService] OpenRouter not available: #{e.message}"
      raise "OpenRouter gem not properly loaded. Please check your configuration."
    end
    response = client.complete(
      messages,
      model: [ participant.model_id ],  # OpenRouter expects model as array
      extras: {
        # Optional parameters can be added here
        # max_tokens: 1000,
        # temperature: 0.7
      }
    )

    # Extract content from response
    content = extract_content_from_response(response)

    # Create message with response
    AssistantMessage.create!(
      conversation: conversation,
      conversation_participant: participant,
      role: Message::ROLE_ASSISTANT,
      model_id: participant.model_id,
      round_number: conversation.current_round,
      content: content,
      metadata: {
        model_name: participant.model_id,
        response_metadata: response.to_h.slice("usage", "model", "created")
      }
    )
  rescue => e
    Rails.logger.error "[LlmService] Error: #{e.message}"

    # Create error message with error flag in metadata
    error_message = AssistantMessage.create!(
      conversation: conversation,
      conversation_participant: participant,
      role: Message::ROLE_ASSISTANT,
      model_id: participant.model_id,
      round_number: conversation.current_round,
      content: "Sorry, I encountered an error generating my response.",
      metadata: { error: e.message, is_error: true }
    )

    # Return the error message instead of raising
    error_message
  end

  private

  def build_messages
    messages = []

    # Add system message with participant's full prompt
    messages << {
      role: "system",
      content: participant.system_prompt_with_topic
    }

    # Add conversation history as individual messages
    conversation.messages.includes(:conversation_participant)
                        .order(:created_at)
                        .last(10) # Limit for context window
                        .each do |msg|
      messages << {
        role: "assistant",
        content: msg.content,
        name: msg.conversation_participant.name # OpenRouter supports name field
      }
    end

    # Add user message to prompt next response
    messages << {
      role: "user",
      content: build_user_message
    }

    messages
  end

  def build_user_message
    if conversation.messages.empty?
      "Please introduce yourself and start discussing: #{conversation.conversation_topic}"
    else
      "Please continue the discussion about: #{conversation.conversation_topic}. Stay true to your character and respond naturally."
    end
  end

  def extract_content_from_response(response)
    # Handle different response formats from OpenRouter
    if response.is_a?(Hash)
      # Standard OpenAI-style response
      response.dig("choices", 0, "message", "content") ||
      response.dig("message", "content") ||
      response["content"] ||
      "No content in response"
    elsif response.respond_to?(:content)
      response.content
    else
      response.to_s
    end
  end
end
