# frozen_string_literal: true

class TurnService
  attr_reader :round, :participant, :logger

  def initialize(round, participant)
    @round = round
    @participant = participant
    @logger = Rails.logger
    
    # Validate participant belongs to this conversation
    validate_participant!
  end

  def execute
    log_info "Generating response for #{participant.name}"
    
    # Execute within transaction for consistency
    ActiveRecord::Base.transaction do
      message = generate_llm_response
      
      # Update round activity timestamp
      round.touch(:last_activity_at)
      
      message
    end
  end

  private

  def generate_llm_response
    # Use existing LlmService for API communication
    llm_service = LlmService.new(round.conversation, participant)
    
    # Generate the response data
    message_data = llm_service.generate_response
    
    # Create message record with round association
    message = Message.create!(
      round: round,
      conversation_participant: message_data[:conversation_participant],
      model_id: message_data[:model_id],
      content: message_data[:content],
      metadata: message_data[:metadata]
    )
    
    log_info "#{participant.name} response: #{message.content.length} chars"
    message
  end

  def log_info(message)
    logger.info "[TurnService] #{message}"
  end

  def validate_participant!
    unless round.conversation.participants.exists?(id: participant.id)
      raise ArgumentError, "Participant #{participant.id} does not belong to conversation #{round.conversation.id}"
    end
  end
end