FactoryBot.define do
  factory :company do
    sequence(:name) { |n| "Fictional Company #{n}" }
  end
end
