class Conversation < ApplicationRecord
  include TurboStreamable
  
  acts_as_chat
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :participants, class_name: "ConversationParticipant", dependent: :destroy

  attr_accessor :current_turn_participant_id # Temporary store for the current speaker's participant ID

  enum :status, {
    interactive: "interactive",
    generating: "generating",
    complete: "complete",
    failed: "failed"
  }

  MAX_MESSAGES_TO_SEND = 20
  MAX_ROUNDS_TO_SEND = 10

  validates :max_rounds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :conversation_topic, presence: true
  validate :must_have_at_least_two_participants, on: :start

  accepts_nested_attributes_for :participants, allow_destroy: true

  before_validation :set_defaults
  before_validation :ensure_user_exists

  delegate :next_speaker, to: :round_manager

  def can_continue?
    # current_round is now a calculated method
    (interactive? || generating?) && current_round <= max_rounds && participants.size > 0
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

  def generate_one_speaker_turn!(participant_to_speak, stream: true)
    unless participant_to_speak
      Rails.logger.error "[Conversation##generate_one_speaker_turn!] Called with nil participant_to_speak."
      return
    end

    Rails.logger.info "[Conversation##generate_one_speaker_turn!] Generating turn for participant: #{participant_to_speak.id} (#{participant_to_speak.name})"

    self.model_id = participant_to_speak.model_id
    self.current_turn_participant_id = participant_to_speak.id

    system_prompt = participant_to_speak.system_prompt_with_topic
    with_instructions(system_prompt, replace: true)

    prompt = if messages.where(role: "assistant").empty?
      "This is the beginning of a conversation. Introduce yourself according to your character and role, then start the discussion about the conversation topic. Be engaging and set the tone for a meaningful exchange."
    else
      "Continue the conversation by responding thoughtfully to the previous message. Stay true to your character and role, and build upon the discussion constructively. IMPORTANT: Only write your own response. Do not write for any other participant."
    end

    Rails.logger.info "--- [RubyLLM CALL] ---"
    Rails.logger.info "Model: #{self.model_id}"
    Rails.logger.info "System Prompt: #{system_prompt.truncate(200)}"
    Rails.logger.info "User Prompt: #{prompt.truncate(200)}"
    Rails.logger.info "Current messages count before ask: #{messages.count}"
    begin
      history_for_log = self.messages.order(:created_at).map { |m| { role: m.role, content: m.content&.truncate(100) } }.to_json
      Rails.logger.info "History: #{history_for_log}"
    rescue => e
      Rails.logger.warn "Could not log history: #{e.message}"
    end
    Rails.logger.info "--------------------"

    message_frame_broadcast = false
    is_first_chunk = true

    Rails.logger.info "About to call ask() method (streaming: #{stream})"
    begin
      if stream
        result = ask(prompt) do |chunk|
          assistant_message = messages.where(role: "assistant").last

          if chunk.content && assistant_message
            unless message_frame_broadcast
              current_participant = participants.find(current_turn_participant_id)
              if current_participant
                broadcast_new_message(assistant_message, current_participant)
                message_frame_broadcast = true
              else
                Rails.logger.error "[Conversation##generate_one_speaker_turn!] Could not find current participant."
              end
              sleep 0.1 # Only sleep during streaming for UX
            end

            if is_first_chunk
              assistant_message.broadcast_update_chunk(chunk.content)
              is_first_chunk = false
            else
              assistant_message.broadcast_append_chunk(chunk.content)
            end
          end
        end
      else
        # Non-streaming version for background jobs
        result = ask(prompt)
      end
      
      Rails.logger.info "ask() method completed, result: #{result.inspect}"
      Rails.logger.info "Messages count after ask: #{messages.count}"
      Rails.logger.info "Assistant messages count after ask: #{messages.where(role: 'assistant').count}"
    rescue => e
      Rails.logger.error "Error in ask() method: #{e.class}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      raise e
    end

    if stream
      broadcast_controls
    end
  end

  def generate_one_round!(stream: true)
    return unless can_continue? && participants.any?

    round_to_generate = self.current_round

    Rails.logger.info "[Conversation##generate_one_round!] Attempting to generate/complete round: #{round_to_generate} for conversation ID: #{id}"
    Rails.logger.info "[Conversation##generate_one_round!] current_round: #{self.current_round}, round_to_generate: #{round_to_generate}"
    Rails.logger.info "[Conversation##generate_one_round!] Current assistant messages count: #{messages.where(role: 'assistant').count}"
    Rails.logger.info "[Conversation##generate_one_round!] Participants count: #{participants.count}"

    participants.ordered.each do |participant|
      break unless can_continue?

      has_spoken = participant.has_spoken_in_round?(round_to_generate)
      Rails.logger.info "[Conversation##generate_one_round!] Participant #{participant.id} (#{participant.name}) has_spoken_in_round?(#{round_to_generate}): #{has_spoken}"

      if has_spoken
        Rails.logger.info "[Conversation##generate_one_round!] Participant #{participant.id} (#{participant.name}) already spoke in round #{round_to_generate}. Skipping."
        next
      end

      Rails.logger.info "[Conversation##generate_one_round!] Participant #{participant.id} (#{participant.name}) speaking for round #{round_to_generate}, conversation ID: #{id}"
      Rails.logger.info "[Conversation##generate_one_round!] Messages count before generate_one_speaker_turn!: #{messages.count}"
      
      generate_one_speaker_turn!(participant, stream: stream)
      
      reload
      Rails.logger.info "[Conversation##generate_one_round!] Messages count after generate_one_speaker_turn!: #{messages.count}"
      Rails.logger.info "[Conversation##generate_one_round!] Assistant messages count after generate_one_speaker_turn!: #{messages.where(role: 'assistant').count}"
    end
    Rails.logger.info "[Conversation##generate_one_round!] Finished attempting to generate/complete round: #{round_to_generate} for conversation ID: #{id}"
  end

  def generate_full_conversation!
    # Don't manually create system messages - ruby_llm will create them via with_instructions
    
    max_rounds.times do |i|
      Rails.logger.info "Generating round #{i + 1}/#{max_rounds} for conversation #{id}"
      generate_one_round!(stream: false)
      reload
    end

    update!(status: :complete)
  rescue => e
    Rails.logger.error "Failed to generate conversation #{id}: #{e.message}\n#{e.backtrace.join("\n")}"
    update!(status: :failed)
  end

  private

  def round_manager
    @round_manager ||= RoundManager.new(self)
  end

  def must_have_at_least_two_participants
    errors.add(:participants, "must have at least 2 participants") if participants.size < 2
  end

  def set_defaults
    if status.blank?
      self.status = :interactive
    end

    if dialogue_instructions.blank?
      self.dialogue_instructions = "Have a thoughtful conversation about the given topic, exploring different perspectives and ideas."
    end

    if max_rounds.blank?
      self.max_rounds = 10
    end
  end

  def ensure_user_exists
    if user.nil?
      self.user = User.anonymous
    end
  end

  def persist_message_completion(message)
    Rails.logger.info "--- [RubyLLM RESPONSE] ---"
    if message
      Rails.logger.info "Status: Success"
      Rails.logger.info "Model ID: #{message.model_id}"
      Rails.logger.info "Tokens: Input=#{message.input_tokens || 'N/A'}, Output=#{message.output_tokens || 'N/A'}"
      Rails.logger.info "Content: #{message.content&.truncate(200)}"

      # Set the conversation_participant based on current_turn_participant_id
      # Ensure this is done *before* super for assistant messages.
      if message.role == "assistant" && current_turn_participant_id.present?
        participant = participants.find_by(id: current_turn_participant_id)
        if participant
          message.conversation_participant = participant
          Rails.logger.info "Assigned conversation_participant: #{participant.name} (ID: #{participant.id}) to message ID: #{message.id || 'new'}"
        else
          Rails.logger.warn "[Conversation##persist_message_completion] Could not find participant with ID: #{current_turn_participant_id} to assign to message."
        end
      elsif message.role == "assistant"
        Rails.logger.warn "[Conversation##persist_message_completion] current_turn_participant_id is blank for assistant message. Participant not set."
      end
    else
      Rails.logger.warn "Status: Failure (message object is nil)"
    end
    Rails.logger.info "-------------------------"

    result = super(message) # Call the original acts_as_chat persistence logic

    # Verify and log after persistence
    if message&.persisted? && message.role == "assistant"
      if message.conversation_participant.nil?
        Rails.logger.warn "[Conversation##persist_message_completion] Message ID #{message.id} (assistant) still has no conversation_participant after super. This is unexpected."
      else
        Rails.logger.info "[Conversation##persist_message_completion] Message ID #{message.id} (assistant) successfully persisted with participant: #{message.conversation_participant.name}"
      end
    end
    
    result
  end

  # Calculated current_round based on assistant messages
  def current_round
    assistant_messages_count = messages.where(role: "assistant").count
    num_participants = participants.count
    return 1 if num_participants.zero? # Default to round 1 if no participants (edge case)
    
    # If no assistant messages yet, it's round 1
    return 1 if assistant_messages_count.zero? 
    
    # Calculate round based on how many full sets of participant turns have occurred
    (assistant_messages_count.to_f / num_participants).ceil
  end
end
