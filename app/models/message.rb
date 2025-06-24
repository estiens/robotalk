class Message < ApplicationRecord
  # Define roles as constants for clarity and to avoid magic strings
  ROLE_USER = "user".freeze
  ROLE_ASSISTANT = "assistant".freeze
  ROLE_SYSTEM = "system".freeze
  ROLE_TOOL = "tool".freeze # If you use tool result messages

  # Define roles as constants for clarity and to avoid magic strings
  ROLE_USER = "user".freeze
  ROLE_ASSISTANT = "assistant".freeze
  ROLE_SYSTEM = "system".freeze
  ROLE_TOOL = "tool".freeze # If you use tool result messages
  # Add other roles as needed, e.g. ROLE_TOOL_RESULT = "tool_result".freeze

  acts_as_message chat_class: "Conversation" # From ruby_llm gem
  belongs_to :conversation
  belongs_to :conversation_participant, optional: true # Links to the AI participant that "spoke" this
  has_many :tool_calls, dependent: :destroy

  # STI discriminator column is 'type' by default.
  # self.inheritance_column = :type

  # This callback sets the round_number when an assistant message shell is first created by acts_as_chat.
  before_create :set_initial_round_number_for_shell

  # Broadcasting for the message shell during streaming.
  # Finalized AssistantMessage instances can have their own broadcasts if needed,
  # typically triggered by their after_create_commit callbacks.
  broadcasts_to ->(message) { [message.conversation, "messages"] },
                  partial: "conversations/message", # Renders the individual message partial
                  target: "conversation-messages"   # Appends/prepends to the div with this ID

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

  def set_initial_round_number_for_shell
    # This callback runs when acts_as_chat creates the initial message shell (before content).
    # For assistant messages, set their round_number to the conversation's current_round.
    if self.role == ROLE_ASSISTANT && self.conversation.present? && self.round_number.nil?
      self.round_number = self.conversation.current_round
      Rails.logger.info "[Message##set_initial_round_number_for_shell] Set round_number to #{self.round_number} for new assistant message shell (ID: #{self.id || 'new'}) in conversation #{conversation.id} (current_round: #{self.conversation.current_round})."
    end
  end
end
