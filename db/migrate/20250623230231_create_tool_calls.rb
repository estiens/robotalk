class CreateToolCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :tool_calls do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.string :tool_call_id
      t.string :name
      t.text :arguments
      t.text :result

      t.timestamps
    end
  end
end
