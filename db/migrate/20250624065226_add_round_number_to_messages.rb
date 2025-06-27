class AddRoundNumberToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :round_number, :integer
    add_index :messages, [ :conversation_id, :round_number ]

    # Populate round_number for existing messages
    reversible do |dir|
      dir.up do
        execute <<-SQL
          WITH numbered_messages AS (
            SELECT id, conversation_id,
                   ROW_NUMBER() OVER (PARTITION BY conversation_id, role = 'assistant' ORDER BY created_at) as rn,
                   role
            FROM messages
            WHERE role = 'assistant'
          )
          UPDATE messages
          SET round_number = numbered_messages.rn
          FROM numbered_messages
          WHERE messages.id = numbered_messages.id
        SQL
      end
    end
  end
end
