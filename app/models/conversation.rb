# frozen_string_literal: true

class Conversation < ApplicationRecord
  include TurboStreamable

  belongs_to :user
  has_many :rounds, dependent: :destroy
  has_many :messages, through: :rounds
  has_many :participants, class_name: 'ConversationParticipant', dependent: :destroy

  enum :status, {
    pending: 'pending',
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
    participants.size >= 2
  end

  def can_continue?
    # Check status first - completed/failed conversations can't continue
    return false if complete? || failed?
    
    # Check if we haven't exceeded max rounds
    rounds_ok = current_round_number < max_rounds

    # Check if we have enough participants
    participants_ok = participants.size >= 2

    rounds_ok && participants_ok
  end
  
  # Current round number based on Round records
  def current_round_number
    rounds.count
  end

  # Backward compatibility alias
  alias_method :current_round, :current_round_number


  # Get current speaker from active round
  def current_speaker
    current_round = rounds.order(:number).last
    return participants.ordered.first unless current_round
    
    current_round.current_participant
  end
  
  def next_speaker
    current_speaker
  end

  # Convenience methods for UI
  def has_rounds?
    rounds.exists?
  end
  
  def latest_round
    rounds.order(:number).last
  end
  
  def is_conversation_complete?
    current_round_number >= max_rounds
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

  # Check if conversation is ready for the next round
  def ready_for_next_round?
    # Should have an active round that is completed and within max rounds
    current_round = rounds.order(:number).last
    return false unless current_round
    return false unless current_round.completed?
    
    can_continue?
  end


  private


  def must_have_at_least_two_participants
    errors.add(:participants, 'must have at least 2 participants') if participants.size < 2
  end

  def set_defaults
    return unless new_record?

    self.status = :pending if status.blank?
    self.dialogue_instructions = 'Have a thoughtful conversation about the given topic, exploring different perspectives and ideas.' if dialogue_instructions.blank?
    self.max_rounds = 10 if max_rounds.blank?
    Rails.logger.debug { "[CONVERSATION CREATE] Setting defaults for conversation - status: #{status}, max_rounds: #{max_rounds}" }
  end

  def ensure_user_exists
    self.user = User.anonymous if user.nil?
  end

  def log_creation
    Rails.logger.info "[CONVERSATION CREATED] Conversation ##{id} created with status: #{status}, max_rounds: #{max_rounds}, participants: #{participants.size}, can_continue?: #{can_continue?}"
  end
end
