class RemoveUniqueConstraintFromConversationParticipants < ActiveRecord::Migration[8.0]
  def change
    # Remove the unique constraint on conversation_id and model
    # This allows multiple participants to use the same model (e.g., two GPT-4 instances with different personalities)
    remove_index :conversation_participants, name: "index_conversation_participants_on_conversation_id_and_model", if_exists: true

    # Add back a non-unique index for performance on the standardized column
    add_index :conversation_participants, [ :conversation_id, :model_id ], name: "index_conversation_participants_on_conversation_id_and_model"
  end
end
