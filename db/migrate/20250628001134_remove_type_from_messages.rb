class RemoveTypeFromMessages < ActiveRecord::Migration[8.0]
  def change
    # Remove STI type column since we're consolidating on one message type
    remove_column :messages, :type, :string
    
    # Remove tool_calls table since we don't use tool calling
    drop_table :tool_calls do |t|
      t.integer :conversation_id, null: false
      t.integer :message_id, null: false
      t.string :tool_call_id
      t.string :name
      t.text :arguments
      t.text :result
      t.timestamps null: false
      t.index [:conversation_id]
      t.index [:message_id]
    end
  end
end
