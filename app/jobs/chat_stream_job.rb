class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find(conversation_id)

    # Generate one round with streaming
    # This job now generates a full round (all participants speak)
    conversation.generate_one_round!
  end
end
