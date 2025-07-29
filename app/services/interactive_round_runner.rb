# frozen_string_literal: true

class InteractiveRoundRunner
  attr_reader :round, :options, :execution_time

  def initialize(round, **options)
    raise ArgumentError, 'Round must be persisted' unless round.persisted?
    
    @round = round
    @options = {
      broadcast: true,
      async_broadcast: true
    }.merge(options)
    @execution_time = nil
  end

  def execute
    start_time = Time.current
    
    begin
      # Create orchestrator and broadcaster
      orchestrator = RoundOrchestrator.new(round)
      broadcaster = create_broadcaster
      
      # Set up comprehensive event callbacks for interactive mode
      setup_event_callbacks(orchestrator, broadcaster)
      
      # Execute the round through orchestrator
      result = orchestrator.execute
      
      @execution_time = Time.current - start_time
      result
      
    rescue StandardError => e
      @execution_time = Time.current - start_time
      Rails.logger.error "[InteractiveRoundRunner] Interactive round execution failed: #{e.message}"
      raise e
    end
  end

  def broadcast_enabled?
    options[:broadcast] == true
  end

  def async_broadcast?
    options[:async_broadcast] == true
  end

  private

  def create_broadcaster
    return nil unless broadcast_enabled?
    
    ConversationBroadcaster.new(round.conversation, mode: :interactive)
  end

  def setup_event_callbacks(orchestrator, broadcaster)
    # Core round lifecycle events
    orchestrator.on(:round_started) do |payload|
      # Round started - could add specific UI feedback here
    end

    orchestrator.on(:round_completed) do |payload|
      broadcaster&.broadcast_round_completed
    end

    orchestrator.on(:round_failed) do |payload|
      broadcaster&.broadcast_error(payload[:reason])
    end

    # Turn-level events for detailed UI feedback
    orchestrator.on(:turn_started) do |payload|
      broadcaster&.broadcast_participant_started(payload[:participant])
    end

    orchestrator.on(:turn_completed) do |payload|
      broadcaster&.broadcast_message_created(payload[:result])
    end
  end
end