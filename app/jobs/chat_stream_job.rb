class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)

    # Generate one round with streaming
    conversation.generate_one_round_with_streaming!
  end
end
