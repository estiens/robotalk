class Conversation < ApplicationRecord
  acts_as_chat
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :participants, class_name: "ConversationParticipant", dependent: :destroy

  # broadcasts_to ->(conversation) { [conversation, "messages"] }

  enum :status, {
    interactive: "interactive",
    generating: "generating",
    complete: "complete",
    failed: "failed"
  }

  validates :max_rounds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :conversation_topic, presence: true
  validate :must_have_at_least_two_participants, on: :start

  accepts_nested_attributes_for :participants, allow_destroy: true

  before_validation :set_defaults
  before_validation :ensure_user_exists

  def current_round
    messages.where(role: "assistant").count
  end

  def can_continue?
    interactive? && current_round < max_rounds
  end

  def next_speaker
    assistant_messages = messages.where(role: "assistant")
    return participants.ordered.first.model_id if assistant_messages.empty?

    last_assistant_message = assistant_messages.last
    Rails.logger.debug "=== NEXT SPEAKER DEBUG ==="
    Rails.logger.debug "Last assistant message model_id: #{last_assistant_message.model_id.inspect}"
    Rails.logger.debug "Last assistant message model_id: #{last_assistant_message.model_id.inspect}"

    current_participant = participants.find_by(model_id: last_assistant_message.model_id)
    Rails.logger.debug "Current participant found: #{current_participant&.model_id.inspect}"

    return nil unless current_participant

    next_participant = participants.ordered.where("turn_order > ?", current_participant.turn_order).first
    next_participant ||= participants.ordered.first
    Rails.logger.debug "Next participant model: #{next_participant.model_id.inspect}"

    next_participant.model_id
  end

  def participant_for_model(model_id)
    participants.find_by(model_id: model_id)
  end

  def models
    participants.ordered.pluck(:model_id)
  end

  def can_start?
    interactive? && participants.size >= 2
  end

  def generate_one_round!
    next_model_speaker = next_speaker
    return unless next_model_speaker

    self.model_id = next_model_speaker

    prompt = if messages.where(role: "assistant").empty?
      "This is the beginning of a conversation. Introduce yourself according to your character and role, then start the discussion about the conversation topic. Be engaging and set the tone for a meaningful exchange."
    else
      "Continue the conversation by responding thoughtfully to the previous message. Stay true to your character and role, and build upon the discussion constructively."
    end

    ask(prompt)
  end


  def generate_full_conversation!
    # Add system messages if not present
    if messages.where(role: "system").empty?
      participants.each do |participant|
        messages.create!(
          role: "system",
          content: participant.system_prompt_with_topic,
          model_id: participant.model_id
        )
      end
    end

    # Generate rounds
    max_rounds.times do |i|
      Rails.logger.info "Generating round #{i + 1}/#{max_rounds} for conversation #{id}"
      generate_one_round!
      # Reload to get latest message state for next_speaker logic
      reload
    end

    update!(status: :complete)
  rescue => e
    Rails.logger.error "Failed to generate conversation #{id}: #{e.message}\n#{e.backtrace.join("\n")}"
    update!(status: :failed)
  end

  private

  def must_have_at_least_two_participants
    errors.add(:participants, "must have at least 2 participants") if participants.size < 2
  end

  def set_defaults
    # Set default status if not provided
    if status.blank?
      self.status = :interactive
    end

    # Set default dialogue_instructions if not provided
    if dialogue_instructions.blank?
      self.dialogue_instructions = "Have a thoughtful conversation about the given topic, exploring different perspectives and ideas."
    end

    # Set default max_rounds if not provided
    if max_rounds.blank?
      self.max_rounds = 10
    end
  end

  def ensure_user_exists
    if user.nil?
      self.user = User.anonymous
    end
  end

  # Overriding RubyLLM persistence hooks for logging
  def persist_new_message
    Rails.logger.info "--- [RubyLLM HOOK] persist_new_message: Creating empty assistant message before API call. ---"
    super # Call the original implementation
  end

  def persist_message_completion(message)
    Rails.logger.info "--- [RubyLLM HOOK] persist_message_completion: API call finished. Response: #{message.inspect} ---"
    super(message) # Call the original implementation
  end
end
