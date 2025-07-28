# frozen_string_literal: true

class Conversation < ApplicationRecord
  include TurboStreamable

  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :participants, class_name: 'ConversationParticipant', dependent: :destroy

  enum :status, {
    pending: 'pending',
    in_progress: 'in_progress',
    generating: 'generating',
    round_ready: 'round_ready',
    complete: 'complete',
    failed: 'failed'
  }

  validates :max_rounds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :conversation_topic, presence: true
  validate :must_have_at_least_two_participants, on: :start

  accepts_nested_attributes_for :participants, allow_destroy: true

  before_validation :set_defaults
  before_validation :ensure_user_exists
  after_create :log_creation

  # Simple state machine methods
  def can_start?
    pending? && participants.size >= 2
  end

  def can_continue?
    # Can continue if pending, in_progress, round_ready, or failed (for retry)
    status_ok = pending? || in_progress? || round_ready? || failed?

    # Check if we haven't exceeded max rounds
    rounds_ok = current_round <= max_rounds

    # Check if we have enough participants
    participants_ok = participants.size >= 2

    result = status_ok && rounds_ok && participants_ok
    Rails.logger.debug do
      "[DEBUG] Conversation ##{id} status: #{status}, pending?: #{pending?}, in_progress?: #{in_progress?}, round_ready?: #{round_ready?}, failed?: #{failed?}, current_round: #{current_round}, max_rounds: #{max_rounds}, participants: #{participants.size}, can_continue?: #{result}"
    end
    result
  end

  def start!
    return false unless can_start?

    update!(status: :in_progress)
    true
  end

  def complete!
    update!(status: :complete)
  end

  def fail!
    Rails.logger.error "[CONVERSATION FAIL] Conversation ##{id} being marked as failed. Current status: #{status}, current_round: #{current_round}, max_rounds: #{max_rounds}, participants: #{participants.size}"
    Rails.logger.error "[CONVERSATION FAIL] Backtrace: #{caller.join("\n")}"
    update!(status: :failed)
  end

  def reset!
    return false unless failed? || complete?

    update!(status: :pending)
    true
  end

  # Delegate complex operations to services
  def current_speaker
    round_manager.next_speaker
  end

  delegate :next_speaker, to: :round_manager

  def ready_for_next_round?
    result = can_continue? && current_round <= max_rounds
    Rails.logger.debug { "[DEBUG] Conversation ##{id} ready_for_next_round?: #{result}, can_continue?: #{can_continue?}, current_round: #{current_round}, max_rounds: #{max_rounds}" }
    result
  end

  # Delegate to RoundService for individual speaker response
  def have_current_speaker_respond!
    RoundService.new(self).have_current_speaker_respond!
  end

  # Delegate to RoundService for full round
  def perform_round!(interactive: true)
    RoundService.new(self).perform_round!(interactive: interactive)
  end

  # Generate full conversation (for background jobs)
  def generate_full_conversation!
    RoundService.new(self).generate_full_conversation!
  end

  # Build conversation history as formatted text
  def conversation_history(limit: nil)
    query = messages.includes(:conversation_participant).order(:created_at)
    query = query.last(limit) if limit

    query.map do |message|
      participant_name = message.conversation_participant&.name || 'Unknown'
      "#{participant_name}: #{message.content}"
    end.join("\n\n")
  end

  # Expected by Message callbacks
  def process_new_message
    # This method is called when a Message is created
    # Currently handled by RoundService, but keeping for compatibility
    Rails.logger.info '[Conversation] Processing new message'
  end

  private

  def round_manager
    @round_manager ||= RoundManager.new(self)
  end

  def must_have_at_least_two_participants
    errors.add(:participants, 'must have at least 2 participants') if participants.size < 2
  end

  def set_defaults
    return unless new_record?

    self.status = :pending if status.blank?
    self.dialogue_instructions = 'Have a thoughtful conversation about the given topic, exploring different perspectives and ideas.' if dialogue_instructions.blank?
    self.max_rounds = 10 if max_rounds.blank?
    self.current_round = 1 if current_round.blank?
    Rails.logger.debug { "[CONVERSATION CREATE] Setting defaults for conversation - status: #{status}, current_round: #{current_round}, max_rounds: #{max_rounds}" }
  end

  def ensure_user_exists
    self.user = User.anonymous if user.nil?
  end

  def log_creation
    Rails.logger.info "[CONVERSATION CREATED] Conversation ##{id} created with status: #{status}, current_round: #{current_round}, max_rounds: #{max_rounds}, participants: #{participants.size}, can_continue?: #{can_continue?}"
  end
end
