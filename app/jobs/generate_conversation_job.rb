class GenerateConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    conversation.generate_full_conversation!
  end
end
