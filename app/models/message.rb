class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  before_create :set_round_number

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

  private

  def set_round_number
    return unless role == "assistant" && conversation.present? && round_number.nil?

    # Count existing assistant messages (this message will be added after callback)
    assistant_message_count = conversation.messages.where(role: "assistant").count
    num_participants = conversation.participants.count

    return if num_participants.zero?

    # Add 1 to count this message that's about to be created
    total_assistant_messages = assistant_message_count + 1
    
    # Use the same calculation as RoundManager for consistency
    self.round_number = (total_assistant_messages.to_f / num_participants).ceil
  end
end
