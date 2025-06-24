class RoundManager
  attr_reader :conversation

  def initialize(conversation)
    @conversation = conversation
  end

  def current_round
    assistant_message_count = conversation.messages.where(role: "assistant").count
    num_participants = conversation.participants.count
    return 0 if num_participants.zero?
    (assistant_message_count.to_f / num_participants).ceil
  end

  def next_speaker
    ordered_participants = conversation.participants.ordered
    return ordered_participants.first if ordered_participants.empty?

    last_assistant_message = conversation.messages.where(role: "assistant").order(:created_at).last
    return ordered_participants.first unless last_assistant_message

    current_speaker_participant = last_assistant_message.conversation_participant
    return nil unless current_speaker_participant

    round_of_last_message = last_assistant_message.round_number
    # If round_number is somehow not set, use current_round calculation
    round_of_last_message ||= current_round
    round_of_last_message = 1 if round_of_last_message == 0

    # Find next participant with a turn_order greater than the current speaker's,
    # who hasn't spoken in this round.
    next_in_order = ordered_participants.find do |p|
      p.turn_order > current_speaker_participant.turn_order && !p.has_spoken_in_round?(round_of_last_message)
    end
    return next_in_order if next_in_order

    # If no such participant, loop back and find the first participant (by turn_order)
    # who hasn't spoken in this round.
    first_to_speak_again_in_round = ordered_participants.find do |p|
      !p.has_spoken_in_round?(round_of_last_message)
    end
    return first_to_speak_again_in_round if first_to_speak_again_in_round

    # If all participants have spoken in the current round, then it's the first participant
    # of the *next* round.
    ordered_participants.first
  end
end
