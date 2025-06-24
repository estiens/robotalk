require 'rails_helper'

RSpec.describe ToolCall, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:tool_call_id) }
    it { should validate_presence_of(:name) }
  end

  describe 'associations' do
    it { should belong_to(:message) }
  end
end
