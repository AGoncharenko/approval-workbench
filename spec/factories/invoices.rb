FactoryBot.define do
  factory :invoice do
    submitted_by { association :user, company: company }
    company { association :company }
    sequence(:vendor_name) { |n| "Fictional Vendor #{n}" }
    total_minor_units { 123_456 }
    currency { "USD" }
    due_date { Date.current + 14 }
    status { "DRAFT" }

    trait(:pending) { status { "PENDING" } }
    trait(:approved) { status { "APPROVED" } }
    trait(:rejected) { status { "REJECTED" } }
  end
end
