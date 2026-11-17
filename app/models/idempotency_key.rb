# A claimed client idempotency key; it exists only for commands that applied (refusals roll it back).
class IdempotencyKey < ApplicationRecord
  belongs_to :approval_event, optional: true
end
