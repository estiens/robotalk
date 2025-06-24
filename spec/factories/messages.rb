FactoryBot.define do
  factory :message do
    association :conversation
    role { "user" }
    content { "This is a test message." }
  end
end
