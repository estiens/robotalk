class CreateConversationParticipants < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_participants do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :model_id, null: false
      t.text :system_prompt
      t.integer :turn_order, null: false

      t.timestamps
    end

    add_index :conversation_participants, [ :conversation_id, :turn_order ], unique: true
    add_index :conversation_participants, [ :conversation_id, :model_id ], unique: true, name: "index_conversation_participants_on_conversation_id_and_model_id"
  end
end
