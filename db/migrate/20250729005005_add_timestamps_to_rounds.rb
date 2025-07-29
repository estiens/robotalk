class AddTimestampsToRounds < ActiveRecord::Migration[8.0]
  def change
    add_column :rounds, :started_at, :datetime
    add_column :rounds, :completed_at, :datetime
    add_column :rounds, :failed_at, :datetime
    # Note: pause_reason and failure_reason columns already exist as paused_reason and failed_reason
    # Remove the duplicate column names from original migration
    rename_column :rounds, :paused_reason, :pause_reason
    rename_column :rounds, :failed_reason, :failure_reason
  end
end
