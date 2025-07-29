# frozen_string_literal: true

class GenerateConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Rails.logger.info "[GenerateConversationJob] Starting background generation for conversation ##{conversation.id}"
    
    # Generate all rounds using BackgroundRoundRunner
    conversation.max_rounds.times do |round_index|
      round_number = round_index + 1
      
      Rails.logger.info "[GenerateConversationJob] Creating round #{round_number} for conversation ##{conversation.id}"
      round = conversation.rounds.create!(number: round_number)
      
      # Execute round using BackgroundRoundRunner (no broadcasting)
      runner = BackgroundRoundRunner.new(round)
      result = runner.execute
      
      # Check if round completed successfully
      unless result[:status] == :completed
        Rails.logger.error "[GenerateConversationJob] Round #{round_number} failed with status: #{result[:status]}"
        conversation.update!(status: 'failed')
        return
      end
      
      Rails.logger.info "[GenerateConversationJob] Round #{round_number} completed for conversation ##{conversation.id}"
    end
    
    # Mark conversation as complete
    conversation.update!(status: 'complete')
    Rails.logger.info "[GenerateConversationJob] Background generation completed for conversation ##{conversation.id}"
    
  rescue StandardError => e
    Rails.logger.error "[GenerateConversationJob] Background generation failed for conversation ##{conversation.id}: #{e.message}"
    Rails.logger.error "[GenerateConversationJob] Error backtrace: #{e.backtrace.join("\n")}"
    
    # Ensure conversation is marked as failed
    conversation.update!(status: 'failed')
    # Re-raise the error for job retry/failure handling
    raise e
  end
end
