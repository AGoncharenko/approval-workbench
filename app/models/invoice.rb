class Invoice < ApplicationRecord
  # Ruby uses the lowercase keys; the database stores the uppercase values (readable in SQL and the audit log).
  STATUSES = %w[DRAFT PENDING APPROVED REJECTED].freeze

  belongs_to :company
  belongs_to :submitted_by, class_name: "User"

  enum :status, STATUSES.index_by(&:downcase), validate: true

  validates :vendor_name, presence: true, length: { maximum: 200 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validates :total_minor_units, numericality: { only_integer: true, in: 0..99_999_999_999_999 }
  validates :due_date, presence: true
  validate { errors.add(:submitted_by, "must belong to the same company") if submitted_by && submitted_by.company_id != company_id }

  def to_param = uuid

  def total = Money.new(total_minor_units, currency)

  def terminal? = approved? || rejected?

  # Seam for add-approval-commands: it replaces this with the invoice's approval_events, oldest first.
  def approval_history = []
end
