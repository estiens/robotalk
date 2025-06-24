class CleanupMessageModelField < ActiveRecord::Migration[8.0]
  def change
    # Remove the duplicate model_id column since we're using model
    remove_column :messages, :model_id, :string
  end
end
