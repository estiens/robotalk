class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.integer :max_rounds
      t.string :model_1
      t.string :model_2

      t.timestamps
    end
  end
end
