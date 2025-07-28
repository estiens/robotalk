# frozen_string_literal: true

# All messages are assistant messages in our simplified system
class Message < ApplicationRecord
  ROLE_ASSISTANT = 'assistant'

  belongs_to :conversation
  belongs_to :conversation_participant, optional: true
  # Removed: has_many :tool_calls (no more tool calling)

  validates :content, presence: true, unless: :streaming_message?
  validates :round_number, presence: true

  before_validation :set_defaults
  after_create_commit :trigger_conversation_processing

  # Safe metadata access
  def metadata
    super || {}
  end

  def metadata_value(key, default = nil)
    metadata[key.to_s] || default
  end

  def error_message?
    metadata_value('is_error') == true
  end

  def streaming_message?
    metadata_value('status') == 'streaming'
  end

  private

  def set_defaults
    self.role = ROLE_ASSISTANT if role.nil?

    return unless conversation.present? && round_number.nil?

    self.round_number = conversation.current_round
  end

  def trigger_conversation_processing
    conversation.process_new_message
  end
end
