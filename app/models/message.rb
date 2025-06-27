class Message < ApplicationRecord
  # We're consolidating to only store assistant messages (actual conversation content)
  # No more user/system messages stored - those are generated on-the-fly for LLM context
  ROLE_ASSISTANT = "assistant".freeze

  belongs_to :conversation
  belongs_to :conversation_participant # Always required now - every message has a speaker
  has_many :tool_calls, dependent: :destroy

  # All messages are assistant messages now, with STI for future extensibility
  validates :role, inclusion: { in: [ ROLE_ASSISTANT ] }
  validates :content, presence: true
  validates :conversation_participant, presence: true
  validates :round_number, presence: true

  # Set round_number for assistant messages based on conversation state
  before_create :set_round_number_for_assistant_messages

  # Broadcasting will be handled manually through LlmService to avoid route issues
  # broadcasts_to removed to prevent automatic broadcast errors

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

  def set_round_number_for_assistant_messages
    if self.conversation.present? && self.round_number.nil?
      self.round_number = self.conversation.current_round
      Rails.logger.info "[Message##set_round_number_for_assistant_messages] Set round_number to #{self.round_number} for message (ID: #{self.id || 'new'}) in conversation #{conversation.id}"
    end
  end
end
