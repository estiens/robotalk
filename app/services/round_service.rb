# frozen_string_literal: true

class RoundService
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def have_current_speaker_respond!
    was_pending = conversation.pending?
    conversation.start! if was_pending

    speaker = conversation.current_speaker
    raise 'No current speaker available' unless speaker

    Rails.logger.info "[RoundService] #{speaker.name} responding in round #{conversation.current_round}"

    # Generate LLM response
    message = LlmService.new(conversation, speaker).generate_response

    # Check if it was an error message
    if message.metadata&.dig('is_error')
      Rails.logger.error "[RoundService] #{speaker.name} failed to respond in round #{conversation.current_round}"
      raise "LLM service failed for #{speaker.name}: #{message.metadata['error']}"
    else
      Rails.logger.info "[RoundService] #{speaker.name} completed response: #{message.content.length} chars"

      # Check if round is complete after this successful response
      if round_complete?
        if advance_round!
          Rails.logger.info "[RoundService] Round #{conversation.current_round - 1} completed after #{speaker.name}'s response"
        else
          Rails.logger.info "[RoundService] Round already advanced by another process after #{speaker.name}'s response"
        end
      end
    end

    message
  rescue StandardError => e
    Rails.logger.error "[RoundService] Failed to have #{speaker&.name || 'unknown'} respond: #{e.message}"
    raise e
  end

  def perform_round!(interactive: true)
    current_round_number = conversation.current_round
    Rails.logger.info "[RoundService] Starting round #{current_round_number} for conversation #{conversation.id}"

    # Have each participant speak in turn order
    conversation.participants.ordered.each do |participant|
      Rails.logger.info "[RoundService] #{participant.name} responding in round #{current_round_number}"

      # Generate LLM response
      message = LlmService.new(conversation, participant).generate_response

      # Check if it was an error message
      if message.metadata&.dig('is_error')
        Rails.logger.error "[RoundService] #{participant.name} failed to respond in round #{current_round_number}"
        raise "LLM service failed for #{participant.name}: #{message.metadata['error']}"
      else
        Rails.logger.info "[RoundService] #{participant.name} completed response: #{message.content.length} chars"
      end
    end

    # Advance to next round
    if advance_round!(interactive: interactive)
      Rails.logger.info "[RoundService] Round #{current_round_number} completed"
    else
      Rails.logger.info "[RoundService] Round #{current_round_number} already completed by another process"
    end
  end

  def generate_full_conversation!
    conversation.start! unless conversation.in_progress?

    Rails.logger.info "[RoundService] Starting full generation: round=#{conversation.current_round}, max=#{conversation.max_rounds}"

    while conversation.current_round <= conversation.max_rounds
      Rails.logger.info "[RoundService] Loop iteration: round=#{conversation.current_round}, max=#{conversation.max_rounds}"
      perform_round!(interactive: false)
      conversation.reload # Refresh state
      Rails.logger.info "[RoundService] After round: round=#{conversation.current_round}, status=#{conversation.status}"
    end

    Rails.logger.info "[RoundService] Loop ended: round=#{conversation.current_round}, max=#{conversation.max_rounds}"

    conversation.complete!
    Rails.logger.info "[RoundService] Full conversation completed after #{conversation.max_rounds} rounds"
  rescue StandardError => e
    Rails.logger.error "[RoundService] Failed to generate conversation #{conversation.id}: #{e.message}"
    Rails.logger.error "[RoundService] Error backtrace: #{e.backtrace.join("\n")}"
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

  def advance_round!(interactive: true)
    current_round_number = conversation.current_round
    new_round = current_round_number + 1
    Rails.logger.info "[RoundService] Advancing from round #{current_round_number} to #{new_round}"

    # Use optimistic concurrency control to prevent race conditions
    # Only advance if we're still in the expected round
    rows_updated = Conversation.where(id: conversation.id, current_round: current_round_number)
                               .update_all(current_round: new_round)

    if rows_updated == 0
      # Someone else already advanced the round
      Rails.logger.warn "[RoundService] Race condition detected: round #{current_round_number} already advanced by another process"
      conversation.reload # Refresh our local state
      return false
    end

    # Refresh conversation state after successful update
    conversation.reload

    # Check if conversation is complete
    if conversation.current_round > conversation.max_rounds
      conversation.complete!
      Rails.logger.info "[RoundService] Conversation complete after #{conversation.max_rounds} rounds"
    elsif interactive
      # Set to round_ready to pause for user input in interactive mode
      conversation.update!(status: :round_ready)
      Rails.logger.info "[RoundService] Round #{current_round_number} completed, ready for round #{conversation.current_round}"
    else
      # In non-interactive mode (full generation), keep in_progress status
      Rails.logger.info "[RoundService] Round #{current_round_number} completed, continuing to round #{conversation.current_round}"
    end
    true
  end
end
