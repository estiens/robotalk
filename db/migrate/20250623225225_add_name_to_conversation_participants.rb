class AddNameToConversationParticipants < ActiveRecord::Migration[8.0]
  def change
    add_column :conversation_participants, :name, :string
  end
end
