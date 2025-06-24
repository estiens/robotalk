module TurboStreamable
  extend ActiveSupport::Concern

  private

  # Broadcast conversation frame update to handle layout transitions  
  def broadcast_conversation_update
    broadcast_replace_to(
      self,
      target: "conversation",
      template: "conversations/show",
      locals: { conversation: self }
    )
  end

  # Broadcast conversation controls update
  def broadcast_controls
    broadcast_replace_to(
      self,
      target: "conversation-controls-container",
      partial: "conversations/controls",
      locals: { conversation: self.reload }
    )
  end

  # Broadcast message with simplified parameters
  def broadcast_new_message(message, participant)
    message.broadcast_append_to(
      [self, "messages"],
      target: "conversation-messages",
      partial: "conversations/message",
      locals: {
        message: message,
        conversation_participant: participant,
        conversation: self,
        index: messages.where(role: "assistant").count - 1
      }
    )
  end
end