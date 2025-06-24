class Message < ApplicationRecord
  # Define roles as constants for clarity and to avoid magic strings
  ROLE_USER = "user".freeze
  ROLE_ASSISTANT = "assistant".freeze
  ROLE_SYSTEM = "system".freeze
  ROLE_TOOL = "tool".freeze # If you use tool result messages

  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  # STI requires the `type` column.
  # self.inheritance_column = :type # This is the default, so not strictly necessary to set

  before_create :set_round_number_for_assistant_shell
  # The advance_conversation_round_if_needed logic will be triggered by AssistantMessage's callback

  # Enable broadcasting for real-time updates of the message shell during streaming
  # This will broadcast the base Message object.
  # When it becomes an AssistantMessage, that specific instance will trigger its own broadcasts if needed.
  broadcasts_to ->(message) { [ message.conversation, "messages" ] }, partial: "conversations/message", target: "conversation-messages"

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    target_id = ActionView::RecordIdentifier.dom_id(self, "content")
    # Ensure content is HTML-safe if it's plain text being inserted as HTML
    safe_chunk_content = ERB::Util.html_escape(chunk_content)
    Turbo::StreamsChannel.broadcast_append_to(
      [ conversation, "messages" ], # Stream target
      target: target_id,            # DOM ID to append to
      html: safe_chunk_content      # The content to append
    )
  end

  # Helper to broadcast the first chunk, replacing the placeholder content
  def broadcast_update_chunk(chunk_content)
    target_id = ActionView::RecordIdentifier.dom_id(self, "content")
    safe_chunk_content = ERB::Util.html_escape(chunk_content)
    Turbo::StreamsChannel.broadcast_update_to(
      [ conversation, "messages" ], # Stream target
      target: target_id,            # DOM ID to update
      html: safe_chunk_content      # The new content
    )
  end

  private

  def set_round_number_for_assistant_shell
    # This callback runs when acts_as_chat creates the initial message shell.
    # We set the round_number based on the conversation's current_round.
    if self.role == ROLE_ASSISTANT && self.conversation.present? && self.round_number.nil?
      self.round_number = self.conversation.current_round
      Rails.logger.info "[Message##set_round_number_for_assistant_shell] Set round_number to #{self.round_number} for new assistant message shell in conversation #{conversation.id}"
    end
  end

  # advance_conversation_round_if_needed is now primarily handled by AssistantMessage's callback
  # or directly in Conversation after an AssistantMessage is finalized.
end
