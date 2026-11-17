module AdminHelper
  def user_role_label(role) = t("users.roles.#{role}")

  def user_role_options = User.roles.keys.map { [ user_role_label(it), it ] }

  # What an audit entry did, e.g. "Approved" or "Role change".
  def audit_action_label(entry)
    entry.role_change? ? t("admin.audit_events.role_change") : t("approvals.actions.#{entry.action}")
  end

  # Filter choices: an event type (all transitions, role changes) or a single invoice action.
  def audit_event_options
    [ [ t("admin.audit_events.transition"), "transition" ], [ t("admin.audit_events.role_change"), "role_change" ] ] +
      AuditFilter::ACTIONS.map { [ t("approvals.actions.#{it}"), it ] }
  end
end
