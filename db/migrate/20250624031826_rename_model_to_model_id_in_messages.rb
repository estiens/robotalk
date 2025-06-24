class RenameModelToModelIdInMessages < ActiveRecord::Migration[8.0]
  def change
    rename_column :messages, :model, :model_id
  end
end
