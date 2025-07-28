# frozen_string_literal: true

class RoundManager
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def next_speaker
    # Return nil if conversation is past max rounds or not active
    return nil if conversation.current_round > conversation.max_rounds || conversation.complete? || conversation.failed?

    # Find the first participant (by turn_order) who hasn't spoken in current round
    conversation.participants.ordered.find do |participant|
      !participant.has_spoken_in_round?(conversation.current_round)
    end
  end
end
