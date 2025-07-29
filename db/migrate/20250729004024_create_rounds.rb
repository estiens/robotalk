class CreateRounds < ActiveRecord::Migration[8.0]
  def change
    create_table :rounds do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :status, default: 'pending', null: false
      t.integer :next_participant_index, default: 0, null: false
      t.text :paused_reason
      t.text :failed_reason
      t.datetime :last_activity_at

      t.timestamps
      
      # Ensure unique round numbers per conversation
      t.index [:conversation_id, :number], unique: true
      # Index for finding rounds by status
      t.index :status
      # Index for finding stale rounds
      t.index :last_activity_at
    end
  end
end
