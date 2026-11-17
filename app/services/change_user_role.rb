# The one command that changes a user's role. Returns a Result whose outcome is one of
# :applied, :unchanged, :forbidden, :not_found or :invalid. Only :applied writes anything:
# the role update and its role_change_events row commit together or not at all.
class ChangeUserRole
  Result = Data.define(:outcome, :user, :from_role, :error) do
    def self.of(outcome, user: nil, from_role: nil, error: nil) = new(outcome:, user:, from_role:, error:)
  end

  def self.call(...) = new(...).call

  def initialize(actor:, user_uuid:, role:)
    @actor = actor
    @user_uuid = user_uuid.to_s
    @role = role.to_s
  end

  def call
    ApplicationRecord.transaction { decide }
  end

  private
    def decide
      # Serialises every role change in the company, so two admins demoting each other can't both pass the admin check.
      company = Company.lock.find(@actor.company_id)
      target = company.users.find_by(uuid: @user_uuid)
      return Result.of(:not_found) unless target
      return Result.of(:forbidden, user: target) if target.id == @actor.id
      return Result.of(:invalid, user: target, error: :role) unless User.roles.key?(@role)
      return Result.of(:unchanged, user: target) if target.role == @role
      return Result.of(:invalid, user: target, error: :last_admin) if target.admin? && company.users.admin.where.not(id: target).none?
      # The actor's current role, read under the lock: an admin demoted since this request began may not act.
      return Result.of(:forbidden, user: target) unless company.users.admin.exists?(id: @actor.id)

      from_role = target.role
      target.update!(role: @role)
      RoleChangeEvent.create!(company:, actor_id: @actor.id, target_user: target, from_role:, to_role: @role)
      Result.of(:applied, user: target, from_role:)
    end
end
