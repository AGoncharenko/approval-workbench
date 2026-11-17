class Invoice < ApplicationRecord
  # Ruby uses the lowercase keys; the database stores the uppercase values (readable in SQL and the audit log).
  STATUSES = %w[DRAFT PENDING APPROVED REJECTED].freeze

  belongs_to :company
  belongs_to :submitted_by, class_name: "User"
  has_many :approval_events, dependent: :restrict_with_exception

  enum :status, STATUSES.index_by(&:downcase), validate: true

  validates :vendor_name, presence: true, length: { maximum: 200 }
  validates :currency, inclusion: { in: Money::CURRENCIES }
  validates :total_minor_units, numericality: { only_integer: true, in: 0..99_999_999_999_999 }
  validates :due_date, presence: true
  before_validation { self.total_minor_units = Money.parse(@amount, currency) if @amount }
  validate :amount_parsed, if: -> { @amount && total_minor_units.nil? }
  validate { errors.add(:submitted_by, "must belong to the same company") if submitted_by && submitted_by.company_id != company_id }

  def to_param = uuid

  # The form's amount: a decimal string, parsed to total_minor_units by the currency's exponent on validation.
  def amount = @amount || (total.amount if total_minor_units && currency)

  def amount=(input)
    @amount = input.to_s
  end

  def total = Money.new(total_minor_units, currency)

  def terminal? = approved? || rejected?

  def approval_history = approval_events.includes(:actor).order(:created_at, :id)

  private
    # Unsupported currencies get their own field error; the amount can only be judged against a known exponent.
    def amount_parsed
      if @amount.blank?
        errors.add(:amount, :blank)
      elsif (decimals = Money::EXPONENTS[currency])
        errors.add(:amount, :invalid_amount, decimals:, currency:, max: Money.new(Money::MAX_MINOR_UNITS, currency).amount)
      end
    end
end
