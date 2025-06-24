class ConversationParticipant < ApplicationRecord
  belongs_to :conversation


  validates :model_id, presence: true
  validates :turn_order, presence: true, uniqueness: { scope: :conversation_id }
  validates :name, presence: true

  scope :ordered, -> { order(:turn_order) }

  before_validation :set_defaults

  def system_prompt_with_topic
    # Build the complete system prompt with base + character + dialogue + topic
    prompt_parts = []

    # 1. Base system prompt (always included)
    prompt_parts << base_system_prompt

    # 2. Character-specific prompt (if provided)
    if character_prompt.present?
      prompt_parts << character_prompt
    end

    # 3. Dialogue instructions (if provided)
    if conversation.dialogue_instructions.present?
      prompt_parts << "Dialogue Instructions: #{conversation.dialogue_instructions}"
    end

    # 4. Conversation topic context (if provided)
    if conversation.conversation_topic.present?
      prompt_parts << "Conversation Topic: #{conversation.conversation_topic}"
    end

    # 5. Custom system prompt override (if provided)
    if system_prompt.present?
      prompt_parts << "Additional Instructions: #{system_prompt}"
    end

    final_prompt = prompt_parts.join("\n\n")

    # Debug logging
    Rails.logger.info "=== System Prompt for #{name} (#{model_id}) ==="
    Rails.logger.info "Character prompt present: #{character_prompt.present?}"
    Rails.logger.info "Dialogue instructions present: #{conversation.dialogue_instructions.present?}"
    Rails.logger.info "Conversation topic present: #{conversation.conversation_topic.present?}"
    Rails.logger.info "System prompt present: #{system_prompt.present?}"
    Rails.logger.info "Final prompt length: #{final_prompt.length} characters"

    final_prompt
  end

  private

  def set_defaults
    # Set default name if not provided
    if name.blank?
      self.name = "Participant #{turn_order || (conversation&.participants&.count || 0) + 1}"
    end

    # Set default turn_order if not provided
    if turn_order.blank?
      max_turn_order = conversation&.participants&.maximum(:turn_order) || 0
      self.turn_order = max_turn_order + 1
    end

    # Set default character_prompt if not provided
    if character_prompt.blank?
      self.character_prompt = "You are a helpful AI assistant participating in this conversation. Be engaging and thoughtful in your responses."
    end
  end

  def base_system_prompt
    other_participants = conversation.participants.where.not(id: id)
    other_names_and_models = other_participants.map { |p| "#{p.name} (#{get_friendly_model_name(p.model_id)})" }.join(", ")

    <<~PROMPT.strip
      You are #{name}, an AI assistant participating in a multi-model conversation. Your underlying model is #{get_friendly_model_name(model_id)}.

      You are conversing with: #{other_names_and_models}

      Guidelines:
      - Be engaging, thoughtful, and authentic in your responses
      - Stay true to your model's characteristics and capabilities
      - Build upon previous messages in the conversation
      - Keep responses conversational and natural (typically 2-4 sentences)
      - Avoid being repetitive or overly formal
      - Respond as #{name} while maintaining your model's unique perspective
    PROMPT
  end

  def get_friendly_model_name(model_identifier)
    # Use Rails helper method via ApplicationController
    ApplicationController.helpers.friendly_model_name(model_identifier)
  end
end
