# The audit trail of status transitions. Written only by TransitionInvoice; never updated or deleted.
class ApprovalEvent < ApplicationRecord
  belongs_to :company
  belongs_to :invoice
  belongs_to :actor, class_name: "User"

  def readonly? = !new_record?
end
