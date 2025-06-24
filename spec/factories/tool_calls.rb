FactoryBot.define do
  factory :tool_call do
    association :message
    tool_call_id { "call_#{SecureRandom.hex(8)}" }
    name { "test_tool" }
    arguments { { arg1: "value1" }.to_json }
  end
end
