class AssistantMessage < Message
  # All messages are now assistant messages, but we keep STI for future extensibility

  # Set role to assistant by default
  before_validation :set_assistant_role

  private

  def set_assistant_role
    self.role = Message::ROLE_ASSISTANT if role.nil?
  end
end
