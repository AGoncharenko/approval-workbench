class Company < ApplicationRecord
  has_many :users, dependent: :restrict_with_exception
  has_many :invoices, dependent: :restrict_with_exception
  has_many :audit_entries

  validates :name, presence: true, length: { maximum: 100 }

  def to_param = uuid
end
