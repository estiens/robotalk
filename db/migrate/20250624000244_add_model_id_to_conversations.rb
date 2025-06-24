class AddModelIdToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :model_id, :string
  end
end
