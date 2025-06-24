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
    
    # Variable to hold the ActiveRecord assistant message for this turn
    # acts_as_chat creates this message shell via on_new_message callback when ask/complete is called.
    # We expect persist_message_completion to be called after the stream to finalize it.
    active_record_assistant_message_for_this_turn = nil

    begin
      result = ask(prompt) do |chunk|
        # On the first chunk, identify the assistant message created for this turn.
        if active_record_assistant_message_for_this_turn.nil?
          # Fetch the latest assistant message, which should be the one acts_as_chat just created.
          active_record_assistant_message_for_this_turn = messages.where(role: "assistant").order(:created_at).last
          if active_record_assistant_message_for_this_turn.nil?
            Rails.logger.error "[Conversation##generate_one_speaker_turn!] CRITICAL: active_record_assistant_message_for_this_turn is nil after first chunk. This should not happen."
            next # Skip this chunk if we can't find the message
          end

          # Assign participant in-memory for the initial broadcast.
          # persist_message_completion will handle the final DB save of this association.
          if current_participant_for_broadcast && active_record_assistant_message_for_this_turn.conversation_participant.nil?
            active_record_assistant_message_for_this_turn.conversation_participant = current_participant_for_broadcast
            Rails.logger.info "[Conversation##generate_one_speaker_turn! StreamBlock] Assigned participant #{current_participant_for_broadcast.name} to in-memory assistant_message (ID: #{active_record_assistant_message_for_this_turn.id}) for initial broadcast."
          end

          # Broadcast the new message shell ONCE.
          if current_participant_for_broadcast
            broadcast_new_message(active_record_assistant_message_for_this_turn, current_participant_for_broadcast)
            message_frame_broadcast = true # Ensure this flag is set if not already
            Rails.logger.info "[Conversation##generate_one_speaker_turn! StreamBlock] Broadcasted new message shell for assistant_message ID: #{active_record_assistant_message_for_this_turn.id} with participant: #{current_participant_for_broadcast.name}"
            sleep 0.1 # UX delay only after the first shell broadcast
          else
            Rails.logger.error "[Conversation##generate_one_speaker_turn! StreamBlock] Could not find current_participant_for_broadcast to broadcast new message shell."
          end
        end

        # Ensure we have the message object to broadcast chunks to.
        unless active_record_assistant_message_for_this_turn
          Rails.logger.error "[Conversation##generate_one_speaker_turn! StreamBlock] active_record_assistant_message_for_this_turn is still nil when trying to broadcast chunk. Skipping chunk."
          next
        end

        if chunk.content 
          if is_first_chunk && message_frame_broadcast # message_frame_broadcast ensures the shell was sent
            active_record_assistant_message_for_this_turn.broadcast_update_chunk(chunk.content)
            is_first_chunk = false
          elsif message_frame_broadcast # Only append if the shell has been broadcasted
            active_record_assistant_message_for_this_turn.broadcast_append_chunk(chunk.content)
          end
        end
      end # End of ask block
      
      Rails.logger.info "ask() method completed. Final result from ask method (not stream): #{result.inspect}"
      Rails.logger.info "Messages count after ask: #{messages.count}"
      Rails.logger.info "Assistant messages count after ask: #{messages.where(role: 'assistant').count}"
    rescue => e
      Rails.logger.error "Error in ask() method: #{e.class}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.join("\n")}"
      raise e
    end

    broadcast_controls # Always broadcast controls as streaming is always on
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

    # Now call super. acts_as_chat's super method should handle saving the message.
    # It uses the attributes from the RubyLLM::Message (like content, tokens)
    # to update the ActiveRecord Message shell that was created earlier.
    # We need to ensure our conversation_participant is also persisted.

    active_record_message = super(message) # This should return the persisted ActiveRecord Message instance

    # After super has run and potentially saved the message,
    # explicitly ensure our conversation_participant is set on the ActiveRecord message.
    if active_record_message.is_a?(::Message) && active_record_message.persisted? && active_record_message.role == "assistant"
      if current_turn_participant_id.present?
        participant_to_assign = participants.find_by(id: current_turn_participant_id)
        if participant_to_assign
          if active_record_message.conversation_participant != participant_to_assign
            active_record_message.update!(conversation_participant: participant_to_assign) # Use update! to save immediately or raise error
            Rails.logger.info "[Conversation##persist_message_completion] Updated ActiveRecord Message ID #{active_record_message.id} with participant: #{participant_to_assign.name} (ID: #{participant_to_assign.id})."
          else
            Rails.logger.info "[Conversation##persist_message_completion] ActiveRecord Message ID #{active_record_message.id} already had correct participant: #{active_record_message.conversation_participant.name}."
          end
        else
          Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: Could not find participant (ID: #{current_turn_participant_id}) to assign to ActiveRecord Message ID #{active_record_message.id} after super."
        end
      else
        Rails.logger.error "[Conversation##persist_message_completion] CRITICAL: current_turn_participant_id was BLANK when trying to assign to ActiveRecord Message ID #{active_record_message.id} after super."
      end

      # Final verification log
      if active_record_message.reload.conversation_participant.nil?
        Rails.logger.error "[Conversation##persist_message_completion] CRITICAL FAILURE FINAL CHECK: ActiveRecord Message ID #{active_record_message.id} (assistant) STILL has no participant after explicit update."
      else
        Rails.logger.info "[Conversation##persist_message_completion] FINAL CHECK: ActiveRecord Message ID #{active_record_message.id} (assistant) has participant: #{active_record_message.conversation_participant.name}."
      end

    elsif message.role == "assistant" # Fallback logging if super didn't return an AR Message
        Rails.logger.warn "[Conversation##persist_message_completion] Verification step: result of super was not a persisted ActiveRecord::Message. Result: #{active_record_message.inspect}. Original RubyLLM::Message (content: #{message.content&.truncate(50)})"
    end
    
    active_record_message # Return the ActiveRecord Message
  end

  # current_round is a database column, not calculated here.
  # Default value is set in set_defaults or migration.
end
