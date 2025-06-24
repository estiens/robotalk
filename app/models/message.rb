class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  # Enable broadcasting for real-time updates
  broadcasts_to ->(message) { [ message.conversation, "messages" ] }, partial: "conversations/message", target: "conversation-messages"

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    # Ensure we're appending to the correct target
    target_id = ActionView::RecordIdentifier.dom_id(self, "content")

    # Use Turbo::StreamsChannel to broadcast the append action
    Turbo::StreamsChannel.broadcast_append_to(
      [ conversation, "messages" ],
      target: target_id,
      html: chunk_content
    )
  end
  # Helper to broadcast the first chunk, replacing the placeholder
  def broadcast_update_chunk(chunk_content)
    target_id = ActionView::RecordIdentifier.dom_id(self, "content")
    Turbo::StreamsChannel.broadcast_update_to(
      [ conversation, "messages" ],
      target: target_id,
      html: chunk_content
    )
  end
end
