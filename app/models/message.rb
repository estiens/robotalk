class Message < ApplicationRecord
  acts_as_message chat_class: "Conversation"
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # For identifying the speaker
  has_many :tool_calls, dependent: :destroy

  # Removed validation: validates :conversation_participant_id, presence: true, if: -> { role == "assistant" }
  # This is because acts_as_chat creates an empty assistant message first,
  # and the participant is assigned in the persist_message_completion (on_end_message) callback.

  before_create :set_round_number
  after_create :advance_conversation_round_if_needed # Restore this callback

  # Enable broadcasting for real-time updates
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

  def advance_conversation_round_if_needed
    return unless role == "assistant" && conversation.present?

    num_participants = conversation.participants.count
    return if num_participants.zero? # Should not happen

    # Count how many assistant messages (speakers) there are for this message's round_number
    assistant_messages_in_this_round = conversation.messages
                                                 .where(role: "assistant", round_number: self.round_number)
                                                 .count

    if assistant_messages_in_this_round >= num_participants
      # This round is complete. Advance the conversation's current_round if it's not already past this one.
      if conversation.current_round <= self.round_number
        new_conversation_round = self.round_number + 1
        conversation.update!(current_round: new_conversation_round)
        Rails.logger.info "[Message##advance_conversation_round_if_needed] Advanced conversation #{conversation.id} to round #{new_conversation_round} because round #{self.round_number} is complete (#{assistant_messages_in_this_round}/#{num_participants} speakers)."
      else
        Rails.logger.info "[Message##advance_conversation_round_if_needed] Conversation #{conversation.id} (current_round: #{conversation.current_round}) is already past this message's round (#{self.round_number}). No advancement needed."
      end
    else
      Rails.logger.info "[Message##advance_conversation_round_if_needed] Round #{self.round_number} for conversation #{conversation.id} is not yet complete. Speakers in round: #{assistant_messages_in_this_round}/#{num_participants}."
    end

    # Always broadcast controls because the state (next speaker, round display) might have changed.
    conversation.broadcast_controls
  end
end
