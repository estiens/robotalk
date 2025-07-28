# frozen_string_literal: true

class Conversation < ApplicationRecord
  include TurboStreamable

  belongs_to :user
  has_many :messages, dependent: :destroy
  # All messages are assistant messages now
  alias assistant_messages messages
  has_many :participants, class_name: 'ConversationParticipant', dependent: :destroy

  enum :status, {
    pending: 'pending',
    in_progress: 'in_progress',
    generating: 'generating',
    complete: 'complete',
    failed: 'failed'
  }

  validates :max_rounds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :conversation_topic, presence: true
  validate :must_have_at_least_two_participants, on: :start

  accepts_nested_attributes_for :participants, allow_destroy: true

  before_validation :set_defaults
  before_validation :ensure_user_exists

  # Simple state machine methods
  def can_start?
    pending? && participants.size >= 2
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
    update!(status: :failed)
  end

  # Delegate complex operations to services
  def current_speaker
    round_manager.next_speaker
  end

  delegate :next_speaker, to: :round_manager

  def can_continue?
    !complete? && !failed? && next_speaker.present?
  end

  # Delegate to RoundService for individual speaker response
  def have_current_speaker_respond!
    RoundService.new(self).have_current_speaker_respond!
  end

  # Delegate to RoundService for full round
  def perform_round!
    RoundService.new(self).perform_round!
  end

  # Generate full conversation (for background jobs)
  def generate_full_conversation!
    RoundService.new(self).generate_full_conversation!
  end

  # Expected by AssistantMessage callbacks
  def process_new_assistant_message
    # This method is called when an AssistantMessage is created
    # Currently handled by RoundService, but keeping for compatibility
    Rails.logger.info '[Conversation] Processing new assistant message'
  end

  private

  def round_manager
    @round_manager ||= RoundManager.new(self)
  end

  def must_have_at_least_two_participants
    errors.add(:participants, 'must have at least 2 participants') if participants.size < 2
  end

  def set_defaults
    self.status = :pending if status.blank?
    self.dialogue_instructions = 'Have a thoughtful conversation about the given topic, exploring different perspectives and ideas.' if dialogue_instructions.blank?
    self.max_rounds = 10 if max_rounds.blank?
    self.current_round = 1 if current_round.blank?
  end

  def ensure_user_exists
    self.user = User.anonymous if user.nil?
  end
end
