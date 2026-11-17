# One row of the audit_entries view: an invoice transition or a role change. Read-only; the view is not writable.
class AuditEntry < ApplicationRecord
  KINDS = %w[transition role_change].freeze

  belongs_to :company
  belongs_to :actor, class_name: "User"
  belongs_to :invoice, optional: true
  belongs_to :target_user, class_name: "User", optional: true

  def readonly? = true

  def role_change? = kind == "role_change"
end
