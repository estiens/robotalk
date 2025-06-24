class RoundManager
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def current_round
    assistant_message_count = conversation.messages.where(role: "assistant").count
    num_participants = conversation.participants.count
    return 0 if num_participants.zero?
    
    result = (assistant_message_count.to_f / num_participants).ceil
    Rails.logger.debug "RoundManager#current_round: #{assistant_message_count} assistant messages / #{num_participants} participants = round #{result}"
    result
  end

  def next_speaker
    ordered_participants = conversation.participants.ordered
    return ordered_participants.first if ordered_participants.empty?

    current_round_num = [current_round, 1].max
    
    # Find the participant with the lowest turn_order who hasn't spoken in this round
    next_speaker = ordered_participants.find do |participant|
      !participant.has_spoken_in_round?(current_round_num)
    end
    
    # If everyone has spoken in this round, start the next round with the first participant
    next_speaker || ordered_participants.first
  end
end
