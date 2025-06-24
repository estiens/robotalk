class AddDialogueInstructionsToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :dialogue_instructions, :text
  end
end
