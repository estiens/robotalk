class RoundManager
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def next_speaker
    ordered_participants = conversation.participants.ordered
    return nil if ordered_participants.empty? # Return nil if there are no participants

    current_round_num = conversation.current_round
    
    # Find the first participant (by turn_order) who has not yet spoken in the current round.
    speaker = ordered_participants.find do |participant|
      !participant.has_spoken_in_round?(current_round_num)
    end

    Rails.logger.info "[RoundManager##next_speaker] For Conversation ID: #{conversation.id}, current_round: #{current_round_num}. Found next speaker: #{speaker&.name || 'None (round complete or no one left)'} (ID: #{speaker&.id})."
    
    speaker # This will be nil if everyone has spoken in the current_round_num
  end
end
