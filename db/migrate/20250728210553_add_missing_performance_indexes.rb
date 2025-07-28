class AddMissingPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Messages table indexes for common query patterns
    add_index :messages, :role
    add_index :messages, :created_at
    add_index :messages, [:conversation_id, :role]
    
    # Conversations table indexes for filtering and ordering
    add_index :conversations, :status
    add_index :conversations, :created_at
    add_index :conversations, [:user_id, :status]
    add_index :conversations, [:user_id, :created_at]
  end
end
