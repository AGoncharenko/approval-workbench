class InvoicePolicy
  # The one rule table for status transitions. add-invoice-submission adds:
  #   "submit" => { from: "draft", to: "pending", role: "requester", author: true }
  # author: true means only the author may act; false means the author may not (segregation of duties).
  TRANSITIONS = {
    "approve" => { from: "pending", to: "approved", role: "approver", author: false },
    "reject" => { from: "pending", to: "rejected", role: "approver", author: false }
  }.freeze

  # Statuses an actor may ever see: drafts are private to their author, so only requesters see them.
  # The list query and the status filter both read this, so they can't disagree.
  def self.visible_statuses(user)
    user.requester? ? Invoice.statuses.keys : Invoice.statuses.keys - [ "draft" ]
  end

  def initialize(user, invoice)
    @user = user
    @invoice = invoice
  end

  # Who may take the action at all, whatever the invoice's status (a "no" here is a 403).
  def permitted?(action)
    rule = TRANSITIONS[action.to_s] or return false
    @invoice.company_id == @user.company_id && @user.role == rule[:role] &&
      (@invoice.submitted_by_id == @user.id) == rule[:author]
  end

  # Whether the action can be taken now; the view shows decision controls only when this is true.
  def transition?(action)
    permitted?(action) && @invoice.status == TRANSITIONS.dig(action.to_s, :from)
  end

  # The one place that decides which invoices an actor can see; index and show both read through it.
  class Scope
    def initialize(user)
      @user = user
    end

    def resolve
      invoices = @user.company.invoices.where(status: InvoicePolicy.visible_statuses(@user))
      @user.requester? ? invoices.where(submitted_by: @user) : invoices
    end
  end
end
