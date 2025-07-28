# frozen_string_literal: true

class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)

    # Generate response from current speaker with streaming
    conversation.have_current_speaker_respond!
  end
end
