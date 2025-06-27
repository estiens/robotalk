class RoundService
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def have_current_speaker_respond!
    conversation.start! if conversation.pending?

    speaker = conversation.current_speaker
    raise "No current speaker available" unless speaker

    Rails.logger.info "[RoundService] #{speaker.name} responding in round #{conversation.current_round}"

    # Generate LLM response
    message = LlmService.new(conversation, speaker).generate_response

    # Check if it was an error message
    if message.metadata&.dig("is_error")
      Rails.logger.error "[RoundService] #{speaker.name} failed to respond in round #{conversation.current_round}"
      raise "LLM service failed for #{speaker.name}: #{message.metadata['error']}"
    else
      Rails.logger.info "[RoundService] #{speaker.name} completed response: #{message.content.length} chars"

      # Check if round is complete after this successful response
      if round_complete?
        advance_round!
        Rails.logger.info "[RoundService] Round #{conversation.current_round - 1} completed after #{speaker.name}'s response"
      end
    end

    message
  end

  def perform_round!
    current_round_number = conversation.current_round
    Rails.logger.info "[RoundService] Starting round #{current_round_number} for conversation #{conversation.id}"

    # Have each participant speak in turn order
    conversation.participants.ordered.each do |participant|
      Rails.logger.info "[RoundService] #{participant.name} responding in round #{current_round_number}"

      # Generate LLM response
      message = LlmService.new(conversation, participant).generate_response

      # Check if it was an error message
      if message.metadata&.dig("is_error")
        Rails.logger.error "[RoundService] #{participant.name} failed to respond in round #{current_round_number}"
        raise "LLM service failed for #{participant.name}: #{message.metadata['error']}"
      else
        Rails.logger.info "[RoundService] #{participant.name} completed response: #{message.content.length} chars"
      end
    end

    # Advance to next round
    advance_round!

    Rails.logger.info "[RoundService] Round #{current_round_number} completed"
  end

  def generate_full_conversation!
    conversation.start! unless conversation.in_progress?

    Rails.logger.info "[RoundService] Starting full generation: round=#{conversation.current_round}, max=#{conversation.max_rounds}"

    while conversation.current_round <= conversation.max_rounds
      Rails.logger.info "[RoundService] Loop iteration: round=#{conversation.current_round}, max=#{conversation.max_rounds}"
      perform_round!
      conversation.reload # Refresh state
      Rails.logger.info "[RoundService] After round: round=#{conversation.current_round}, status=#{conversation.status}"
    end

    Rails.logger.info "[RoundService] Loop ended: round=#{conversation.current_round}, max=#{conversation.max_rounds}"

    conversation.complete!
    Rails.logger.info "[RoundService] Full conversation completed after #{conversation.max_rounds} rounds"
  rescue => e
    Rails.logger.error "[RoundService] Failed to generate conversation #{conversation.id}: #{e.message}"
    conversation.fail!
    raise e
  end

  private

  def round_complete?
    # Check if all participants have spoken in the current round
    conversation.participants.ordered.all? do |participant|
      participant.has_spoken_in_round?(conversation.current_round)
    end
  end

  def advance_round!
    current_round_number = conversation.current_round
    new_round = current_round_number + 1
    Rails.logger.info "[RoundService] Advancing from round #{current_round_number} to #{new_round}"

    conversation.update!(current_round: new_round)

    # Check if conversation is complete
    if conversation.current_round > conversation.max_rounds
      conversation.complete!
      Rails.logger.info "[RoundService] Conversation complete after #{conversation.max_rounds} rounds"
    end
  end
end
