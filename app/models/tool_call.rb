class ToolCall < ApplicationRecord
  acts_as_tool_call message_class: "Message", message_foreign_key: "message_id"

  # RubyLLM expects certain methods for tool call integration
  validates :tool_call_id, presence: true
  validates :name, presence: true

  # Serialize arguments as JSON
  serialize :arguments, coder: JSON
  serialize :result, coder: JSON
end
