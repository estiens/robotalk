class RenameModelToModelIdInConversationParticipants < ActiveRecord::Migration[8.0]
  def change
    rename_column :conversation_participants, :model, :model_id
  end
end
