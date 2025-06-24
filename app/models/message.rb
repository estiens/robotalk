class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  has_many :tool_calls, dependent: :destroy

  # broadcasts_to ->(message) { [message.conversation, "messages"] }

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    broadcast_append_to [ conversation, "messages" ], # Target the stream
      target: ActionView::RecordIdentifier.dom_id(self, "content"), # Target the content div inside the message frame
      html: chunk_content # Append the raw chunk
  end
end
