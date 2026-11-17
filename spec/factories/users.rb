FactoryBot.define do
  factory :user do
    company
    sequence(:name) { |n| "Test User #{n}" }
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "test-password-123" }
    role { "requester" }

    trait(:approver) { role { "approver" } }
    trait(:admin) { role { "admin" } }
  end
end
