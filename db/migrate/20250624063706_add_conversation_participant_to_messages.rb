class AddConversationParticipantToMessages < ActiveRecord::Migration[7.1]
  def change
    add_reference :messages, :conversation_participant, null: true, foreign_key: true
  end
end
