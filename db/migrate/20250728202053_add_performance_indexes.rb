class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Add indexes for performance improvements identified in code review
    
    # Messages table indexes for common queries
    add_index :messages, :role unless index_exists?(:messages, :role)
    add_index :messages, :created_at unless index_exists?(:messages, :created_at)
    add_index :messages, [:conversation_id, :role] unless index_exists?(:messages, [:conversation_id, :role])
    
    # Conversations table indexes for filtering and ordering
    add_index :conversations, :status unless index_exists?(:conversations, :status)
    add_index :conversations, :created_at unless index_exists?(:conversations, :created_at)
    add_index :conversations, [:user_id, :status] unless index_exists?(:conversations, [:user_id, :status])
    add_index :conversations, [:user_id, :created_at] unless index_exists?(:conversations, [:user_id, :created_at])
  end
end
