class User < ApplicationRecord
  has_secure_password
  belongs_to :company
  has_many :sessions, dependent: :destroy

  enum :role, { requester: "requester", approver: "approver", admin: "admin" }, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { maximum: 100 }

  def to_param = uuid
end
