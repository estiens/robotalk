class AssistantMessage < Message
  # This subclass will represent finalized assistant messages.
  # It inherits all attributes and associations from Message.

  # We can add specific validations or methods here if needed in the future,
  # but for now, its primary purpose is to allow us to easily query and
  # broadcast these types of messages distinctly.

  # Ensure that when an AssistantMessage is created/found, its role is 'assistant'.
  # This could also be handled by ensuring `type` is only set when role is 'assistant'.
  default_scope { where(role: ROLE_ASSISTANT) } # ROLE_ASSISTANT should be defined in Message

  # Callbacks specific to AssistantMessage completion can go here.
  # For example, after an AssistantMessage is fully formed and saved,
  # we might trigger round advancement.
  after_create :advance_conversation_round_if_needed_from_assistant # Renamed to avoid conflict if base class has it

  private

  def advance_conversation_round_if_needed_from_assistant
    # Delegate to the conversation's logic for advancing rounds,
    # now that this assistant message is confirmed and saved.
    # This keeps round logic centralized if preferred, or implement here.
    conversation.advance_round_for_assistant_message(self)
  end
end
