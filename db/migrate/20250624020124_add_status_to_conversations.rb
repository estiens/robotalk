class AddStatusToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :status, :string
  end
end
