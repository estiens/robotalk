class AddCharacterPromptToConversationParticipants < ActiveRecord::Migration[8.0]
  def change
    add_column :conversation_participants, :character_prompt, :text
  end
end
