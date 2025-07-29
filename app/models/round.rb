# frozen_string_literal: true

class Round < ApplicationRecord
  include AASM

  belongs_to :conversation
  has_many :messages, dependent: :destroy
  
  validates :number, presence: true, uniqueness: { scope: :conversation_id }
  validates :status, presence: true
  validates :next_participant_index, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # AASM state machine
  aasm column: :status do
    state :pending, initial: true
    state :in_progress
    state :paused
    state :completed
    state :failed
    state :timed_out
    
    event :start do
      transitions from: :pending, to: :in_progress
      after do
        self.started_at = Time.current
        touch(:last_activity_at)
      end
    end
    
    event :pause do
      transitions from: :in_progress, to: :paused
      after do |reason = nil|
        self.pause_reason = reason || 'Paused'
      end
    end
    
    event :resume do
      transitions from: :paused, to: :in_progress
      after do
        self.pause_reason = nil
        touch(:last_activity_at)
      end
    end
    
    event :complete do
      transitions from: :in_progress, to: :completed
      after do
        self.completed_at = Time.current
      end
    end
    
    event :fail do
      transitions from: [:in_progress, :paused], to: :failed
      after do |reason = nil|
        self.failure_reason = reason if reason
        self.failed_at = Time.current
      end
    end
    
    event :timeout do
      transitions from: [:in_progress, :paused], to: :timed_out
      after do
        self.failed_at = Time.current
      end
    end
  end
  
  # Get the current participant who should speak next (efficient single query)
  def current_participant
    return nil if all_participants_have_spoken?
    
    conversation.participants.ordered[next_participant_index]
  end
  
  # Check if all participants have spoken in this round
  def all_participants_have_spoken?
    next_participant_index >= conversation.participants.count
  end
  
  # Get participants that still need to speak in this round (inefficient - prefer current_participant)
  def participants_to_process
    # DEPRECATED: Creates N+1 queries. Use current_participant for better performance.
    conversation.participants.ordered.offset(next_participant_index)
  end
  
  # Advance to the next participant
  def advance_participant!
    increment!(:next_participant_index)
    touch(:last_activity_at)
  end
  
  # Get progress percentage for UI
  def progress_percentage
    return 100 if completed?
    return 0 if next_participant_index.zero?
    
    (next_participant_index.to_f / conversation.participants.count * 100).round
  end
  
  # Get round duration
  def duration
    return nil unless started_at
    
    end_time = completed_at || failed_at || Time.current
    end_time - started_at
  end
  
  # Convenience methods for checking execution results
  def execution_successful?
    completed?
  end
  
  def execution_failed?
    failed? || timed_out?
  end
  
  def can_be_resumed?
    paused?
  end
end