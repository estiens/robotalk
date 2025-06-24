class Conversation < ApplicationRecord
  acts_as_chat
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :participants, class_name: "ConversationParticipant", dependent: :destroy

  attr_accessor :current_turn_participant_id # Temporary store for the current speaker's participant ID

  # Broadcasting for Conversation model itself is temporarily removed to isolate create issue.
  # We will rely on Message model's broadcasts for show page updates for now.

  enum :status, {
    interactive: "interactive",
    generating: "generating",
    complete: "complete",
    failed: "failed"
  }

  # Configuration for message history management
  MAX_MESSAGES_TO_SEND = 20 # Adjust based on your needs
  MAX_ROUNDS_TO_SEND = 10   # Alternative: limit by rounds instead of messages

  validates :max_rounds, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :conversation_topic, presence: true
  validate :must_have_at_least_two_participants, on: :start

  accepts_nested_attributes_for :participants, allow_destroy: true

  before_validation :set_defaults
  before_validation :ensure_user_exists

  def current_round
    assistant_message_count = messages.where(role: "assistant").count
    num_participants = participants.count
    return 0 if num_participants.zero? # Avoid division by zero
    (assistant_message_count.to_f / num_participants).ceil # Use ceil to ensure partial rounds count as the next round
  end

  def can_continue?
    interactive? && current_round < max_rounds
  end

  def next_speaker
    assistant_messages = messages.where(role: "assistant")
    # Always return the participant object or nil
    return participants.ordered.first if assistant_messages.empty?

    last_assistant_message = assistant_messages.last
    Rails.logger.debug "=== NEXT SPEAKER DEBUG ==="
    Rails.logger.debug "Last assistant message model_id: #{last_assistant_message.model_id.inspect}"
    Rails.logger.debug "Last assistant message model_id: #{last_assistant_message.model_id.inspect}"

    current_participant = participants.find_by(model_id: last_assistant_message.model_id)
    Rails.logger.debug "Current participant found: #{current_participant&.model_id.inspect}"

    return nil unless current_participant

    next_participant = participants.ordered.where("turn_order > ?", current_participant.turn_order).first
    next_participant ||= participants.ordered.first
    Rails.logger.debug "Next participant object: #{next_participant.inspect}" # Log the whole object

    next_participant # Return the full participant object
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

  def generate_one_speaker_turn!(participant_to_speak)
    unless participant_to_speak
      Rails.logger.error "[Conversation##generate_one_speaker_turn!] Called with nil participant_to_speak."
      return
    end

    Rails.logger.info "[Conversation##generate_one_speaker_turn!] Generating turn for participant: #{participant_to_speak.id} (#{participant_to_speak.name})"

    self.model_id = participant_to_speak.model_id # For acts_as_chat
    self.current_turn_participant_id = participant_to_speak.id # For persist_new_message hook

    system_prompt = participant_to_speak.system_prompt_with_topic
    with_instructions(system_prompt, replace: true)

    prompt = if messages.where(role: "assistant").empty?
      "This is the beginning of a conversation. Introduce yourself according to your character and role, then start the discussion about the conversation topic. Be engaging and set the tone for a meaningful exchange."
    else
      "Continue the conversation by responding thoughtfully to the previous message. Stay true to your character and role, and build upon the discussion constructively. IMPORTANT: Only write your own response. Do not write for any other participant."
    end

    # --- Enhanced Logging for the API Call ---
    Rails.logger.info "--- [RubyLLM CALL] ---"
    Rails.logger.info "Model: #{self.model_id}"
    Rails.logger.info "System Prompt: #{system_prompt.truncate(200)}"
    Rails.logger.info "User Prompt: #{prompt.truncate(200)}"
    begin
      history_for_log = self.messages.order(:created_at).map { |m| { role: m.role, content: m.content&.truncate(100) } }.to_json
      Rails.logger.info "History: #{history_for_log}"
    rescue => e
      Rails.logger.warn "Could not log history: #{e.message}"
    end
    Rails.logger.info "--------------------"
    # --- End Logging ---

    # Track if we've broadcast the initial message frame and if it's the first chunk
    message_frame_broadcast = false
    is_first_chunk = true

    # Use streaming with a block
    ask(prompt) do |chunk| # Do not pass model_id as kwarg
      assistant_message = messages.where(role: "assistant").last

      if chunk.content && assistant_message
        # First, ensure the message frame exists in the UI
        unless message_frame_broadcast
          assistant_message.broadcast_append_to(
            [ self, "messages" ],
            target: "conversation-messages",
            partial: "conversations/message",
            locals: {
              message: assistant_message,
              message_model_id: next_speaking_participant.model_id,
              conversation_participant: next_speaking_participant,
              conversation: self,
              index: messages.where(role: "assistant").count - 1,
              view_mode: "live"
            }
          )
          message_frame_broadcast = true
          sleep 0.1 # Small delay to ensure frame is rendered
        end

        # On the first chunk, update the content div to replace the "Thinking..." indicator.
        # On subsequent chunks, append to the content div.
        if is_first_chunk
          assistant_message.broadcast_update_chunk(chunk.content)
          is_first_chunk = false
        else
          assistant_message.broadcast_append_chunk(chunk.content)
        end
      end
    end

    # After streaming is complete, broadcast a custom event and update the controls
    broadcast_action_to(
      self,
      action: :dispatch_event,
      target: "conversation",
      name: "conversation:completed",
      detail: { conversation_id: id }
    )
    broadcast_replace_to(
      self,
      target: "conversation-controls-container",
      partial: "conversations/controls",
      locals: { conversation: self.reload }
    )
  end

  # New method to generate a full round (all participants speak once)
  # Generates a full round where each participant speaks once,
  # using the participant's state to determine who still needs to speak.
  def generate_one_round!
    return unless can_continue? && participants.any?

    # Determine the target round number we are working on.
    # `current_round` is `ceil(assistant_messages_count / num_participants)`.
    # If 0 assistant messages, current_round = 0. We want to generate for round 1.
    # If 1 assistant message (3 participants), current_round = 1. We want to generate for round 1.
    # So, round_to_generate should be current_round, unless current_round is 0, then it's 1.
    round_to_generate = (self.current_round == 0) ? 1 : self.current_round

    Rails.logger.info "[Conversation##generate_one_round!] Attempting to generate/complete round: #{round_to_generate} for conversation ID: #{id}"

    participants.ordered.each do |participant|
      # Stop if the conversation cannot continue (e.g., max_rounds reached or error)
      break unless can_continue?

      # Check if this participant has already spoken in the current round_to_generate
      if participant.has_spoken_in_round?(round_to_generate)
        Rails.logger.info "[Conversation##generate_one_round!] Participant #{participant.id} (#{participant.name}) already spoke in round #{round_to_generate}. Skipping."
        next
      end

      Rails.logger.info "[Conversation##generate_one_round!] Participant #{participant.id} (#{participant.name}) speaking for round #{round_to_generate}, conversation ID: #{id}"
      generate_one_speaker_turn!(participant) # Pass the explicit participant

      # Reload is important here:
      # - `can_continue?` needs the latest message count.
      # - The next iteration's `participant.has_spoken_in_round?` might be affected if the same participant
      #   somehow got to speak twice (though our loop prevents this for *this* round).
      # - Most importantly, ensures that if an error occurs during `generate_one_speaker_turn!`,
      #   the loop continues with a fresh state.
      reload
    end
    Rails.logger.info "[Conversation##generate_one_round!] Finished attempting to generate/complete round: #{round_to_generate} for conversation ID: #{id}"
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
        self.current_turn_participant_id = nil # Clear after use
      end
    end

    # Generate rounds
    max_rounds.times do |i|
      Rails.logger.info "Generating round #{i + 1}/#{max_rounds} for conversation #{id}"
      generate_one_round! # Correctly calls the new method that iterates through participants
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
    Rails.logger.info "--- [RubyLLM HOOK] persist_new_message: Creating empty assistant message before API call. Current participant_id to assign: #{self.current_turn_participant_id} ---"
    new_message_shell = super # Call the original implementation from acts_as_chat
    if new_message_shell && new_message_shell.persisted? && self.current_turn_participant_id.present?
      # Ensure the shell is saved and ID is present before trying to update_column
      # Calculate and set the round number for the new message
      num_participants_for_round_calc = participants.count
      if num_participants_for_round_calc.zero?
        Rails.logger.error "[Conversation##persist_new_message] Zero participants found, cannot calculate round_number."
        # Decide on a fallback or raise an error. For now, let's log and potentially set a default or skip.
        # This case should ideally be prevented by validations.
        calculated_round_number = 1 # Fallback, or handle error appropriately
      else
        # Count assistant messages *before* this new one is fully persisted
        # The `super` call in `acts_as_chat` creates the shell, so `messages.where(role: "assistant")`
        # will include the current shell if we are not careful.
        # However, the shell is empty at this stage.
        # A robust way is to count persisted, non-empty assistant messages.
        # Or, given the flow, `messages.where(role: "assistant").count` *before* this message is fully formed
        # (i.e. before its content is set) is effectively the count of *previous* assistant messages.
        # `acts_as_chat` creates an empty shell, then calls API, then fills content.
        # The `round_number` is being set on the shell *before* the API call.

        # Let's count assistant messages that are NOT the current shell.
        # The `new_message_shell` is the one being created.
        existing_assistant_messages_count = messages.where(role: "assistant").where.not(id: new_message_shell.id).count
        calculated_round_number = (existing_assistant_messages_count.to_f / num_participants_for_round_calc).floor + 1
      end

      new_message_shell.update_columns(
        conversation_participant_id: self.current_turn_participant_id,
        round_number: calculated_round_number
      )
      Rails.logger.info "--- [RubyLLM HOOK] persist_new_message: Assigned conversation_participant_id #{self.current_turn_participant_id} and round_number #{calculated_round_number} to new message shell ID #{new_message_shell.id} ---"
    elsif new_message_shell
      Rails.logger.warn "--- [RubyLLM HOOK] persist_new_message: New message shell created (ID: #{new_message_shell.id if new_message_shell.persisted?}), but current_turn_participant_id was blank or shell not persisted. ---"
    else
      Rails.logger.error "--- [RubyLLM HOOK] persist_new_message: super did not return a message shell. ---"
    end
    new_message_shell # Return the (potentially updated) message shell
  end

  def persist_message_completion(message)
    # --- Enhanced Logging for the API Response ---
    Rails.logger.info "--- [RubyLLM RESPONSE] ---"
    if message
      Rails.logger.info "Status: Success"
      # The message hook runs before the new message is saved, so an ID may not be present yet.
      # We rely on the log from persist_new_message for the shell ID.
      Rails.logger.info "Model ID: #{message.model_id}"
      Rails.logger.info "Tokens: Input=#{message.input_tokens || 'N/A'}, Output=#{message.output_tokens || 'N/A'}"
      Rails.logger.info "Content: #{message.content&.truncate(200)}"
    else
      Rails.logger.warn "Status: Failure (message object is nil)"
    end
    Rails.logger.info "-------------------------"
    # --- End Logging ---
    super(message) # Call the original implementation
  end
end
