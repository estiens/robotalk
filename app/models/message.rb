class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  before_create :set_round_number
  after_create :advance_conversation_round_if_needed

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

  def advance_conversation_round_if_needed
    return unless role == "assistant" && conversation.present?

    # Check if this message completes a round
    current_round_messages = conversation.messages.where(role: "assistant", round_number: round_number).count
    num_participants = conversation.participants.count
    
    # If all participants have spoken in this round, advance to next round
    if current_round_messages == num_participants && conversation.current_round < round_number
      conversation.update_column(:current_round, round_number)
      Rails.logger.info "Advanced conversation #{conversation.id} to round #{round_number}"
      
      # Broadcast the round indicator update
      conversation.broadcast_round_indicator if conversation.respond_to?(:broadcast_round_indicator)
    end
  end
end
