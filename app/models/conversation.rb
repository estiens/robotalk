class Conversation < ApplicationRecord
  include TurboStreamable
  
  acts_as_chat # From ruby_llm gem
  belongs_to :user

  # Fetches all messages regardless of STI type. Used by acts_as_chat for history.
  has_many :messages, dependent: :destroy
  
  # Specifically fetches finalized assistant messages for display and application logic.
  has_many :assistant_messages, -> { order(created_at: :asc) }, class_name: "AssistantMessage"
  
  has_many :participants, class_name: "ConversationParticipant", dependent: :destroy

  attr_accessor :current_turn_participant_id # Transient store for the current speaker's participant ID

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
    # current_round is a database column
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

  def generate_one_speaker_turn!(participant_to_speak) # Removed stream parameter
    unless participant_to_speak
      Rails.logger.error "[Conversation##generate_one_speaker_turn!] Called with nil participant_to_speak."
      return
    end

    Rails.logger.info "[Conversation##generate_one_speaker_turn!] Generating turn for participant: #{participant_to_speak.id} (#{participant_to_speak.name})"

    # Ensure current_turn_participant_id is set on the conversation instance
    # This is crucial for persist_message_completion to pick it up.
    self.current_turn_participant_id = participant_to_speak.id 
    self.model_id = participant_to_speak.model_id # acts_as_chat uses this to set on the message

    system_prompt = participant_to_speak.system_prompt_with_topic
    # with_instructions is part of ruby_llm, it sets system prompts for the next 'ask' call.
    # It's correct to call it here to set the context for the specific participant.
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
    # Ensure current_participant is fetched once before the loop for efficiency and consistency
    current_participant_for_broadcast = participants.find_by(id: current_turn_participant_id)
    unless current_participant_for_broadcast
      Rails.logger.error "[Conversation##generate_one_speaker_turn!] CRITICAL: Could not find current_participant_for_broadcast with ID: #{current_turn_participant_id} before ask block."
      # Potentially raise an error or handle this case, as subsequent logic will fail.
    end

    Rails.logger.info "About to call ask() method (streaming is always on)"
    
    # This variable will hold the ActiveRecord assistant message created by acts_as_chat
    # for the current turn. It's created as an empty shell by an on_new_message callback
    # when ask() is called.
    ar_message_shell_for_this_turn = nil

    begin
      result = ask(prompt) do |chunk|
        if ar_message_shell_for_this_turn.nil?
          # This is the first chunk (or just before it).
          # acts_as_chat should have created the empty assistant message shell.
          ar_message_shell_for_this_turn = messages.where(role: "assistant").order(:created_at).last
          
          if ar_message_shell_for_this_turn.nil?
            Rails.logger.error "[Conversation##generate_one_speaker_turn!] CRITICAL: Could not find the assistant message shell created by acts_as_chat. Aborting stream for this turn."
            # Consider breaking the ask block or raising an error if this happens.
            next 
          end

          # Assign the correct participant IN MEMORY for the initial broadcast.
          # The final DB persistence of this is handled by persist_message_completion.
          if current_participant_for_broadcast && ar_message_shell_for_this_turn.conversation_participant_id != current_participant_for_broadcast.id
            ar_message_shell_for_this_turn.conversation_participant = current_participant_for_broadcast
            Rails.logger.info "[Conversation##generate_one_speaker_turn! StreamBlock] In-memory assignment of participant #{current_participant_for_broadcast.name} to new assistant message shell ID #{ar_message_shell_for_this_turn.id}."
          end
          
          # Broadcast the new message shell (which includes participant info due to in-memory assignment)
          if current_participant_for_broadcast
            broadcast_new_message(ar_message_shell_for_this_turn, current_participant_for_broadcast)
            message_frame_broadcast = true # Flag that the shell has been sent
            Rails.logger.info "[Conversation##generate_one_speaker_turn! StreamBlock] Broadcasted new message shell for Message ID #{ar_message_shell_for_this_turn.id} by #{current_participant_for_broadcast.name}."
            sleep 0.1 # Small UX delay
          else
            Rails.logger.error "[Conversation##generate_one_speaker_turn! StreamBlock] CRITICAL: current_participant_for_broadcast is nil. Cannot broadcast new message shell."
          end
        end

        # Ensure we have the message object to broadcast chunks to.
        unless ar_message_shell_for_this_turn
          Rails.logger.error "[Conversation##generate_one_speaker_turn! StreamBlock] ar_message_shell_for_this_turn is nil when trying to broadcast chunk. Skipping."
          next
        end

        if chunk.content && message_frame_broadcast # Only stream if shell was broadcast
          if is_first_chunk
            ar_message_shell_for_this_turn.broadcast_update_chunk(chunk.content)
            is_first_chunk = false
          else
            ar_message_shell_for_this_turn.broadcast_append_chunk(chunk.content)
          end
        end
      end # End of ask block
      
      Rails.logger.info "ask() method completed. Final result from ask method (not stream): #{result.inspect}" # This `result` is from the `ask` method itself, often nil for streaming.
      Rails.logger.info "Messages count after ask: #{messages.count}"
      Rails.logger.info "Assistant messages count after ask: #{messages.where(role: 'assistant').count}"
    rescue => e
      Rails.logger.error "Error in ask() method: #{e.class}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      raise e
    end

    broadcast_controls # Always broadcast controls as streaming is always on
    # self.current_turn_participant_id = nil # Let it be overwritten by the next turn
  end

  def generate_one_round! # Removed stream parameter
    return unless can_continue? && participants.any?

    round_to_generate = self.current_round # Keep this as it's used for has_spoken_in_round?

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
      
      generate_one_speaker_turn!(participant) # Removed stream argument
      
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
      generate_one_round! # Removed stream argument; assumes background generation is also effectively streaming to DB
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
      # This is critical for assistant messages.
      if message.role == "assistant"
        if current_turn_participant_id.present?
          participant = participants.find_by(id: current_turn_participant_id)
          if participant
            message.conversation_participant = participant # Assign the association
            Rails.logger.info "[Conversation##persist_message_completion] Participant #{participant.name} (ID: #{participant.id}) WILL BE SET for message ID: #{message.id || 'new'}."
          else
            # This is a critical issue if a participant ID was expected but not found.
            Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: Could not find participant with ID: #{current_turn_participant_id} for assistant message. Message will lack a participant."
          end
        else
          # This is also critical if an assistant message is being processed without a current_turn_participant_id.
          Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: current_turn_participant_id is BLANK for assistant message. Message will lack a participant."
        end
      end
    else
      Rails.logger.warn "[Conversation##persist_message_completion] Status: Failure (message object is nil)"
    end
    Rails.logger.info "-------------------------"

    # The `message` argument is a RubyLLM::Message instance from the gem.
    # `super(message)` calls acts_as_chat's internal persistence.
    # This finds/creates an ActiveRecord `::Message` (the shell created by on_new_message)
    # and updates it with content, tokens, etc., from the RubyLLM::Message.
    # It should return the finalized ActiveRecord `::Message` instance.
    ar_message_shell = super(message) # This is a base Message instance, potentially updated.

    if ar_message_shell.is_a?(::Message) && ar_message_shell.persisted? && ar_message_shell.role == Message::ROLE_ASSISTANT
      # This is an assistant message shell that has been persisted by acts_as_chat.
      # We now "promote" it to an AssistantMessage and ensure its final associations.
      
      unless self.current_turn_participant_id.present?
        Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: self.current_turn_participant_id is BLANK for Message shell ID #{ar_message_shell.id}. Cannot finalize as AssistantMessage."
        return ar_message_shell 
      end

      participant_for_this_turn = participants.find_by(id: self.current_turn_participant_id)

      unless participant_for_this_turn
        Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: Could not find ConversationParticipant with ID: #{self.current_turn_participant_id} to finalize AssistantMessage from shell ID #{ar_message_shell.id}."
        return ar_message_shell
      end

      # Update the type and other final attributes directly on the existing record.
      # The `round_number` should have been set by `set_initial_round_number_for_shell` on the Message.
      # The `model_id` on the message is set by acts_as_chat using `self.model_id` from the Conversation.
      update_attrs = {
        type: "AssistantMessage",
        conversation_participant_id: participant_for_this_turn.id,
        content: message.content, # from RubyLLM::Message
        input_tokens: message.input_tokens,
        output_tokens: message.output_tokens
        # model_id is already set by acts_as_chat on the shell
        # round_number is already set by before_create on the shell
      }
      
      ar_message_shell.update_columns(update_attrs) # Bypasses callbacks on Message, directly updates DB.
      
      # Reload as an AssistantMessage instance to trigger its callbacks (like after_create_commit)
      # and to ensure we have the correctly typed object.
      finalized_assistant_message = AssistantMessage.find(ar_message_shell.id)

      Rails.logger.info "[Conversation##persist_message_completion] Successfully promoted Message shell ID #{ar_message_shell.id} to AssistantMessage ID #{finalized_assistant_message.id} and associated with participant: #{finalized_assistant_message.conversation_participant.name}."
      
      # The AssistantMessage's after_create_commit callback (`trigger_conversation_processing`)
      # will call `conversation.process_new_assistant_message(self)`.
      
      return finalized_assistant_message
      
    elsif message.role == Message::ROLE_ASSISTANT 
      Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: `super(message)` did not return a persisted ActiveRecord::Message for an assistant role. Result: #{ar_message_shell.inspect}. RubyLLM::Message content: #{message.content&.truncate(50)}"
    end
    
    ar_message_shell # Return whatever super gave us if not an assistant message
  end

  # This method is called by AssistantMessage's after_create_commit callback
  def process_new_assistant_message(assistant_message)
    Rails.logger.info "[Conversation##process_new_assistant_message] Processing finalized AssistantMessage ID: #{assistant_message.id}, Round: #{assistant_message.round_number}."
    return unless assistant_message.persisted? && assistant_message.is_a?(AssistantMessage) && assistant_message.round_number.present?

    num_participants = self.participants.count
    return if num_participants.zero?

    # Count how many AssistantMessages (speakers) there are for this message's round_number
    # Use self.assistant_messages to query only finalized AssistantMessage instances.
    assistant_messages_in_this_round = self.assistant_messages
                                           .where(round_number: assistant_message.round_number)
                                           .count

    if assistant_messages_in_this_round >= num_participants
      # This round is complete based on finalized AssistantMessages.
      if self.current_round <= assistant_message.round_number
        new_conversation_round = assistant_message.round_number + 1
        self.update!(current_round: new_conversation_round)
        Rails.logger.info "[Conversation##process_new_assistant_message] Advanced conversation #{self.id} to round #{new_conversation_round} because round #{assistant_message.round_number} is complete (#{assistant_messages_in_this_round}/#{num_participants} speakers)."
      else
        Rails.logger.info "[Conversation##process_new_assistant_message] Conversation #{self.id} (current_round: #{self.current_round}) is already past this message's round (#{assistant_message.round_number}). No advancement needed."
      end
    else
      Rails.logger.info "[Conversation##process_new_assistant_message] Round #{assistant_message.round_number} for conversation #{self.id} is not yet complete. Speakers in round: #{assistant_messages_in_this_round}/#{num_participants}."
    end
    self.broadcast_controls # Update UI for next speaker, round number, etc.
  end

  # current_round is a database column, not calculated here.
  # Default value is set in set_defaults or migration.
end
