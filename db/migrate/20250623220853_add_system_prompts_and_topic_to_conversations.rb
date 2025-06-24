class AddSystemPromptsAndTopicToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :conversation_topic, :text
    add_column :conversations, :system_prompt_a, :text
    add_column :conversations, :system_prompt_b, :text
  end
end
