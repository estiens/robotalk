class AddRoundToMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :messages, :round, null: false, foreign_key: true
  end
end
