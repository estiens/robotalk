# frozen_string_literal: true

class BackgroundRoundRunner
  attr_reader :round, :options, :execution_time

  SLOW_EXECUTION_THRESHOLD = 2.0 # seconds

  def initialize(round, **options)
    raise ArgumentError, 'Round must be persisted' unless round.persisted?
    
    @round = round
    @options = {
      broadcast: false,     # Always false for background runner
      log_progress: true
    }.merge(options)
    # Ensure broadcast is always disabled for background runner
    @options[:broadcast] = false
    @execution_time = nil
  end

  def execute
    start_time = Time.current
    
    begin
      # Create orchestrator with minimal callback overhead
      orchestrator = RoundOrchestrator.new(round)
      
      # Set up minimal event callbacks for background mode
      setup_minimal_callbacks(orchestrator)
      
      # Execute the round through orchestrator
      result = orchestrator.execute
      
      @execution_time = Time.current - start_time
      log_slow_execution if execution_time > SLOW_EXECUTION_THRESHOLD
      
      result
      
    rescue StandardError => e
      @execution_time = Time.current - start_time
      log_execution_error(e)
      raise e
    end
  end

  def broadcast_enabled?
    false # Always false for background runner
  end

  def log_progress?
    options[:log_progress] == true
  end

  private

  def setup_minimal_callbacks(orchestrator)
    # Only essential callbacks for background processing
    orchestrator.on(:round_started) do |payload|
      log_progress_event("Background round started: #{round.id}")
    end

    orchestrator.on(:round_completed) do |payload|
      log_progress_event("Background round completed: #{round.id}")
    end

    orchestrator.on(:round_failed) do |payload|
      log_progress_event("Background round failed: #{round.id} - #{payload[:reason]}")
    end

    # Skip turn-level callbacks to minimize overhead in background mode
  end

  def log_progress_event(message)
    return unless log_progress?
    
    Rails.logger.info "[BackgroundRoundRunner] #{message}"
  end

  def log_execution_error(error)
    Rails.logger.error "[BackgroundRoundRunner] Background round error: #{round.id}"
    Rails.logger.error "[BackgroundRoundRunner] #{error.message}"
  end

  def log_slow_execution
    return unless log_progress?
    
    Rails.logger.warn "[BackgroundRoundRunner] Long-running background round: #{round.id} took #{execution_time.round(2)}s"
  end
end