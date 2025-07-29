# frozen_string_literal: true

class RoundOrchestrator
  attr_reader :round, :logger

  def initialize(round)
    @round = round
    @logger = Rails.logger
    @callbacks = Hash.new { |h, k| h[k] = [] }
  end

  # Register callback for specific events
  def on(event_name, &block)
    @callbacks[event_name.to_sym] << block
    self # Enable chaining
  end

  # Execute the round with resumability support
  def execute
    log_info "Starting round #{round.number} execution"
    
    # Start the round if it's pending, resume if paused
    if round.pending?
      round.start!
    elsif round.paused?
      round.resume!
    end
    
    notify(:round_started, {
      round: round,
      conversation: round.conversation,
      total_participants: round.conversation.participants.count
    })

    # Process remaining participants efficiently (one at a time)
    while (participant = round.current_participant)
      success = execute_turn_safely(participant)
      
      # Stop if turn failed or round was paused/failed
      break unless success
      
      # Advance to next participant
      round.advance_participant!
    end

    # Complete round if all participants have spoken
    if round.in_progress? && round.all_participants_have_spoken?
      round.complete!  # Bang method handles save
      notify(:round_completed, {
        round: round,
        conversation: round.conversation
      })
      log_info "Round #{round.number} completed successfully"
    end

    # Return execution result
    { status: round.status.to_sym, round: round }
  ensure
    # Prevent memory leaks by clearing callback storage
    @callbacks.clear
  end

  private

  def execute_turn_safely(participant)
    notify(:turn_started, {
      round: round,
      participant: participant,
      progress: round.progress_percentage
    })

    begin
      # Generate response through TurnService
      result = TurnService.new(round, participant).execute
      
      notify(:turn_completed, {
        round: round,
        participant: participant,
        result: result,
        progress: round.progress_percentage
      })
      
      log_info "#{participant.name} completed turn in round #{round.number}"
      true # Continue processing
      
    rescue LlmService::LlmApiError => e
      # For now, treat all LLM API errors as unrecoverable
      # In the future, we could differentiate between rate limits (pause) vs other errors (fail)
      handle_round_failure(e)
      false # Stop processing
      
    rescue StandardError => e
      # Unrecoverable error - fail the round and re-raise
      handle_round_failure(e)
      raise e # Re-raise for caller to handle
    end
  end

  def handle_round_failure(error)
    round.fail!(error.message)  # Bang method handles save
    notify(:round_failed, {
      round: round,
      error: error,
      reason: error.message
    })
    log_error "Round #{round.number} failed: #{error.message}"
  end

  # Publish events to registered callbacks
  def notify(event_name, payload)
    @callbacks[event_name.to_sym].each do |callback|
      callback.call(payload)
    rescue StandardError => e
      log_error "Event callback error for '#{event_name}': #{e.message}"
      # Don't let callback errors break the core flow
    end
  end

  def log_info(message)
    logger.info "[RoundOrchestrator] #{message}"
  end

  def log_error(message)
    logger.error "[RoundOrchestrator] #{message}"
  end
end