class RemoveModelFieldsFromConversations < ActiveRecord::Migration[8.0]
  def change
    remove_column :conversations, :model_1, :string
    remove_column :conversations, :model_2, :string
    remove_column :conversations, :system_prompt_a, :text
    remove_column :conversations, :system_prompt_b, :text
  end
end
