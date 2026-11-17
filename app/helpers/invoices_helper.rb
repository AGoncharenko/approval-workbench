module InvoicesHelper
  def invoice_status_label(status) = t("invoices.statuses.#{status}")

  # Filter choices follow the visibility rule, so a reviewer is never offered "Draft".
  def invoice_status_options(user)
    InvoicePolicy.visible_statuses(user).map { [ invoice_status_label(it), it ] }
  end

  def invoices_empty_message(status:, user:)
    if status
      t("invoices.empty.filtered", status: invoice_status_label(status).downcase)
    else
      t(user.requester? ? "invoices.empty.requester" : "invoices.empty.reviewer")
    end
  end
end
