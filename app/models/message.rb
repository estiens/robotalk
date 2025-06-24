class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  validates :conversation_participant_id, presence: true, if: -> { role == "assistant" }

  before_create :set_round_number
  after_create :advance_conversation_round_if_needed # Restore this callback

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
    # Add 1 to count this message that's about to be created.
    assistant_message_count_for_this_new_message = conversation.messages.where(role: "assistant").count + 1
    num_participants = conversation.participants.count

    return if num_participants.zero?
    
    # Calculate round number for this specific message
    self.round_number = (assistant_message_count_for_this_new_message.to_f / num_participants).ceil
    Rails.logger.info "[Message##set_round_number] Set round_number to #{self.round_number} for new assistant message in conversation #{conversation.id}"
  end

  def advance_conversation_round_if_needed # Restore this method
    return unless role == "assistant" && conversation.present?

    # Check if this message completes a round for the *current message's round_number*
    # This message has already been created, so its round_number is set.
    messages_in_this_round = conversation.messages.where(role: "assistant", round_number: self.round_number).count
    num_participants = conversation.participants.count

    return if num_participants.zero? # Should not happen if validation is correct

    # If all participants have spoken in this round, advance conversation.current_round
    if messages_in_this_round == num_participants
      # Ensure we only advance if the conversation's current_round is indeed this round or an earlier one.
      # This prevents advancing multiple times if messages from the same round are processed out of order (though unlikely with after_create).
      if conversation.current_round <= self.round_number
        new_conversation_round = self.round_number + 1
        conversation.update!(current_round: new_conversation_round) # Use update! to ensure it saves or raises error
        Rails.logger.info "[Message##advance_conversation_round_if_needed] Advanced conversation #{conversation.id} to round #{new_conversation_round} because round #{self.round_number} is complete."
        conversation.broadcast_controls # Trigger Turbo Stream update for controls
      else
        Rails.logger.info "[Message##advance_conversation_round_if_needed] Conversation #{conversation.id} is already at round #{conversation.current_round}, which is beyond this message's round #{self.round_number}. No advancement needed."
      end
    else
      Rails.logger.info "[Message##advance_conversation_round_if_needed] Round #{self.round_number} for conversation #{conversation.id} is not yet complete. Messages in round: #{messages_in_this_round}/#{num_participants}."
      # Even if the round isn't complete, the controls might need updating (e.g. next speaker)
      conversation.broadcast_controls
    end
  end
end
