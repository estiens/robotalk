class RemoveConversationFromMessages < ActiveRecord::Migration[8.0]
  def change
    remove_reference :messages, :conversation, null: false, foreign_key: true
  end
end
