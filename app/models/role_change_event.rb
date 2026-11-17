# The audit trail of role changes. Written only by ChangeUserRole; never updated or deleted.
class RoleChangeEvent < ApplicationRecord
  belongs_to :company
  belongs_to :actor, class_name: "User"
  belongs_to :target_user, class_name: "User"

  def readonly? = !new_record?
end
