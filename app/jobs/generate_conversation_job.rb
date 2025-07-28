# frozen_string_literal: true

class GenerateConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    conversation.generate_full_conversation!
  rescue StandardError => e
    # Ensure conversation is marked as failed
    conversation.fail!
    # Re-raise the error to be caught by the test
    raise e
  end
end
