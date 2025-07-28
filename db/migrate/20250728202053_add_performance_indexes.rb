class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Add indexes for performance improvements identified in code review
    add_index :messages, [:conversation_id, :round_number], name: 'index_messages_on_conversation_and_round'
    add_index :messages, :conversation_participant_id unless index_exists?(:messages, :conversation_participant_id)
    add_index :conversation_participants, :conversation_id unless index_exists?(:conversation_participants, :conversation_id)
  end
end
