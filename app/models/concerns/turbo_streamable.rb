# frozen_string_literal: true

module TurboStreamable
  extend ActiveSupport::Concern

  # Broadcast conversation frame update to handle layout transitions
  def broadcast_conversation_update
    broadcast_replace_to(
      self,
      target: 'conversation',
      template: 'conversations/show',
      locals: { conversation: self }
    )
  end

  # Broadcast message with simplified parameters
  def broadcast_new_message(message_shell, participant_for_shell)
    # message_shell is the base Message instance created by acts_as_chat
    # participant_for_shell is the ConversationParticipant it will belong to (assigned in-memory for this broadcast)
    message_shell.broadcast_append_to(
      [self, 'messages'], # Stream to the conversation's "messages" channel
      target: 'conversation-messages', # DOM ID of the container for all messages
      partial: 'conversations/message', # The partial to render for this new message shell
      locals: {
        message: message_shell, # Pass the shell
        # The partial _message.html.erb will use message.conversation_participant,
        # which should be set in-memory before this broadcast.
        conversation: self,
        # Index can be based on existing assistant messages for animation delay,
        # or simply 0 if this is the only way new messages appear.
        index: assistant_messages.count
      }
    )
    Rails.logger.info "[TurboStreamable##broadcast_new_message] Broadcasted new message shell for Message ID #{message_shell.id}, Participant: #{participant_for_shell&.name}"
  end

  # Broadcast conversation controls update
  # This is now public
  def broadcast_controls
    broadcast_replace_to(
      self,
      target: 'conversation-controls-container',
      partial: 'conversations/controls',
      locals: { conversation: reload } # Ensure fresh data
    )
  end
end
