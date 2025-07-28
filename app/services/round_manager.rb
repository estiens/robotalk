# frozen_string_literal: true

class RoundManager
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def next_speaker
    # Return nil if conversation is past max rounds or not active
    return nil if conversation.current_round > conversation.max_rounds || conversation.complete? || conversation.failed?

    current_round = conversation.current_round

    # Get IDs of participants who have already spoken in this round
    spoken_participant_ids = conversation.messages
                                       .where(round_number: current_round)
                                       .pluck(:conversation_participant_id)
                                       .compact

    # Find first participant (by turn_order) who hasn't spoken yet
    conversation.participants
              .ordered
              .where.not(id: spoken_participant_ids)
              .first
  end
end
