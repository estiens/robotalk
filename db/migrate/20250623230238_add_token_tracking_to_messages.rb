class AddTokenTrackingToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :input_tokens, :integer
    add_column :messages, :output_tokens, :integer
    add_column :messages, :model_id, :string
  end
end
