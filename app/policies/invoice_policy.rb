class InvoicePolicy
  # Statuses an actor may ever see: drafts are private to their author, so only requesters see them.
  # The list query and the status filter both read this, so they can't disagree.
  def self.visible_statuses(user)
    user.requester? ? Invoice.statuses.keys : Invoice.statuses.keys - [ "draft" ]
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
