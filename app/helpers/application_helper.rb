module ApplicationHelper
  def conversation_has_content_issues?(conversation)
    conversation.messages.any? { |m| m.content.blank? }
  end

  def content_missing_count(conversation)
    conversation.messages.count { |m| m.content.blank? }
  end

  def conversation_debug_info(conversation)
    {
      total_messages: conversation.messages.count,
      system_messages: conversation.messages.where(role: "system").count,
      assistant_messages: conversation.messages.where(role: "assistant").count,
      content_missing: content_missing_count(conversation),
      participants: conversation.participants.count,
      current_round: conversation.current_round,
      max_rounds: conversation.max_rounds,
      can_continue: conversation.can_continue?
    }
  end
end
