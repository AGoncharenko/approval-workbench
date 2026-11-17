class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
  # Company comes only from the signed-in user, never from params or the cookie.
  delegate :company, to: :user, allow_nil: true
end
