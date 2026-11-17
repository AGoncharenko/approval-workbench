class User < ApplicationRecord
  has_secure_password
  belongs_to :company
  has_many :sessions, dependent: :destroy
  has_many :submitted_invoices, class_name: "Invoice", foreign_key: :submitted_by_id, inverse_of: :submitted_by, dependent: :restrict_with_exception

  enum :role, { requester: "requester", approver: "approver", admin: "admin" }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }

  def to_param = uuid
end
