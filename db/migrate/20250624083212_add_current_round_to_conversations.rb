# frozen_string_literal: true

class AddCurrentRoundToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :current_round, :integer, default: 1, null: false
  end
end
