# frozen_string_literal: true

# Base class for round execution strategies
class BaseRoundRunner
  attr_reader :round, :orchestrator

  def initialize(round)
    @round = round
    @orchestrator = RoundOrchestrator.new(round)
    setup_callbacks
  end

  def execute
    orchestrator.execute
  end

  protected

  # Abstract method - subclasses must implement
  def setup_callbacks
    raise NotImplementedError, "Subclasses must implement setup_callbacks"
  end

  def log_info(message)
    Rails.logger.info "[#{self.class.name}] #{message}"
  end

  def log_error(message)
    Rails.logger.error "[#{self.class.name}] #{message}"
  end
end