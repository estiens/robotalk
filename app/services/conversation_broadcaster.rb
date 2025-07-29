# frozen_string_literal: true

class ConversationBroadcaster
  # Turbo Stream Constants
  MESSAGES_STREAM_TARGET = 'messages'
  LOADING_TARGET = 'message-loading'
  CONVERSATION_TARGET = 'conversation'
  MESSAGES_CONTAINER_TARGET = 'conversation-messages'

  # Streaming Partials
  STREAMING_INDICATOR_PARTIAL = 'shared/streaming_indicator'
  MESSAGE_PARTIAL = 'conversations/message'
  CONVERSATION_FRAME_PARTIAL = 'conversations/conversation_frame'
  ERROR_MESSAGE_PARTIAL = 'shared/error_message'

  VALID_MODES = [:interactive, :background].freeze

  attr_reader :conversation, :mode

  def initialize(conversation, mode: :interactive)
    raise ArgumentError, 'Conversation cannot be nil' if conversation.nil?
    raise ArgumentError, "Invalid mode: #{mode}. Valid modes: #{VALID_MODES.join(', ')}" unless VALID_MODES.include?(mode)

    @conversation = conversation
    @mode = mode
  end

  # Broadcast that a participant has started responding
  def broadcast_participant_started(participant)
    return unless interactive_mode?
    
    if participant.nil?
      Rails.logger.warn "[ConversationBroadcaster] Attempted to broadcast with nil participant"
      return
    end

    safe_broadcast do
      Turbo::StreamsChannel.broadcast_update_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: LOADING_TARGET,
        partial: STREAMING_INDICATOR_PARTIAL,
        locals: {
          model_name: participant.model_id,
          participant_name: participant.name
        }
      )
    end
  end

  # Broadcast that a new message has been created
  def broadcast_message_created(message)
    return unless interactive_mode?
    
    if message.nil?
      Rails.logger.warn "[ConversationBroadcaster] Attempted to broadcast with nil message"
      return
    end

    unless message.round.conversation == conversation
      Rails.logger.error "[ConversationBroadcaster] Message does not belong to conversation #{conversation.id}"
      return
    end

    safe_broadcast do
      Turbo::StreamsChannel.broadcast_append_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: MESSAGES_CONTAINER_TARGET,
        partial: MESSAGE_PARTIAL,
        locals: {
          message: message,
          conversation: conversation,
          index: conversation.messages.count - 1
        }
      )
    end
  end

  # Broadcast that a round has completed
  def broadcast_round_completed
    return unless interactive_mode?

    # Clear loading indicator
    safe_broadcast do
      Turbo::StreamsChannel.broadcast_update_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: LOADING_TARGET,
        html: ''
      )
    rescue StandardError => e
      Rails.logger.error "[ConversationBroadcaster] Failed to clear loading indicator: #{e.message}"
    end

    # Update conversation frame
    safe_broadcast do
      Turbo::StreamsChannel.broadcast_replace_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: CONVERSATION_TARGET,
        partial: CONVERSATION_FRAME_PARTIAL,
        locals: { conversation: conversation }
      )
    rescue StandardError => e
      Rails.logger.error "[ConversationBroadcaster] Failed to update conversation frame: #{e.message}"
    end
  end

  # Broadcast an error message
  def broadcast_error(error_message)
    return unless interactive_mode?

    sanitized_error = sanitize_error_message(error_message)

    # Clear loading indicator first
    safe_broadcast do
      Turbo::StreamsChannel.broadcast_update_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: LOADING_TARGET,
        html: ''
      )
    rescue StandardError => e
      Rails.logger.error "[ConversationBroadcaster] Failed to clear loading on error: #{e.message}"
    end

    # Broadcast error message
    safe_broadcast do
      Turbo::StreamsChannel.broadcast_append_to(
        [conversation, MESSAGES_STREAM_TARGET],
        target: MESSAGES_CONTAINER_TARGET,
        partial: ERROR_MESSAGE_PARTIAL,
        locals: { error: sanitized_error }
      )
    rescue StandardError => e
      Rails.logger.error "[ConversationBroadcaster] Failed to broadcast error message: #{e.message}"
    end
  end

  private

  def interactive_mode?
    mode == :interactive
  end

  def safe_broadcast
    yield
  rescue StandardError => e
    Rails.logger.error "[ConversationBroadcaster] Broadcasting failed: #{e.message}"
    # Don't re-raise - broadcasting failures shouldn't break core logic
  end

  def sanitize_error_message(error_message)
    return 'An unknown error occurred' if error_message.blank?
    
    # Strip HTML tags for security using Rails sanitizer
    Rails::Html::FullSanitizer.new.sanitize(error_message.to_s)
  end
end