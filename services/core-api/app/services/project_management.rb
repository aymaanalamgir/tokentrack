# All multi-record project writes serialize on the project row and recheck a
# fresh policy inside the lock, so a queued operation cannot use a revoked grant.
class ProjectManagement
  class InvalidOperation < StandardError; end
  class Forbidden < StandardError; end

  def initialize(actor)
    @actor = actor
  end

  def create(attributes)
    actor = fresh_actor
    require_permission!(actor.status == "active" && AccessPolicy.new(actor).create_project?)
    attrs = attributes.symbolize_keys
    raise InvalidOperation, "New projects must start planned or active" unless %w[planned active].include?(attrs.fetch(:status, "planned"))
    lead = eligible_administrator(attrs.delete(:initial_lead_id).presence || @actor.id)
    Project.transaction do
      project = Project.create!(attrs.slice(:name, :description, :status).merge(
        organization_id: @actor.organization_id, created_by: @actor,
        slug: attrs[:slug].presence || attrs[:name].to_s.parameterize,
        status: attrs.fetch(:status, "planned")
      ))
      ProjectMembership.create!(organization_id: project.organization_id, project: project, user: lead, project_role: "owner")
      grant_lead(project, lead)
      ProjectMembership.create!(organization_id: project.organization_id, project: project, user: @actor, project_role: "reviewer") unless lead.id == @actor.id
      project
    end
  end

  def update(project, attributes)
    with_project(project) do |record, policy|
      require_permission!(policy.project_administrator?(record))
      attrs = attributes.symbolize_keys.slice(:name, :description, :status)
      status = attrs.delete(:status)
      if attrs.any?
        require_permission!(policy.edit_project?(record))
        record.assign_attributes(attrs)
      end
      if status && status != record.status
        require_permission!(policy.lifecycle_project?(record))
        unless Project::TRANSITIONS.key?(status)
          record.errors.add(:status, "is not valid")
          raise ActiveRecord::RecordInvalid, record
        end
        unless Project::TRANSITIONS.fetch(record.status).include?(status)
          raise InvalidOperation, "Invalid project lifecycle transition"
        end
        record.archived_from_status = record.status if status == "archived"
        record.status = status
      end
      record.save!
      record
    end
  end

  def add_member(project, user_id, role)
    with_project(project) do |record, policy|
      require_permission!(policy.manage_project_members?(record))
      user = eligible_user(user_id)
      ProjectMembership.create!(organization_id: record.organization_id, project: record, user: user, project_role: role || "contributor")
    end
  end

  def update_member(project, membership_id, role)
    with_project(project) do |record, policy|
      require_permission!(policy.manage_project_members?(record))
      membership = record.active_project_memberships.find(membership_id)
      membership.update!(project_role: role)
      membership
    end
  end

  def remove_member(project, membership_id)
    with_project(project) do |record, policy|
      require_permission!(policy.manage_project_members?(record))
      membership = record.active_project_memberships.find(membership_id)
      grants = RoleAssignment.where(organization_id: record.organization_id, project_id: record.id, role: "project_lead")
      if grants.exists?(user_id: membership.user_id) && grants.count <= 1
        raise InvalidOperation, "Transfer ownership before removing the last authorized administrator"
      end
      grants.where(user_id: membership.user_id).destroy_all
      membership.update!(left_at: Time.current)
      membership
    end
  end

  def transfer(project, user_id)
    with_project(project) do |record, policy|
      require_permission!(policy.transfer_project?(record))
      target = eligible_administrator(user_id)
      membership = record.active_project_memberships.find_or_initialize_by(user_id: target.id)
      membership.assign_attributes(organization_id: record.organization_id, project_role: "owner")
      membership.save!
      record.active_project_memberships.where(project_role: %w[owner lead]).where.not(id: membership.id).update_all(project_role: "contributor", updated_at: Time.current)
      RoleAssignment.where(organization_id: record.organization_id, project_id: record.id, role: "project_lead").destroy_all
      grant_lead(record, target)
      record
    end
  end

  private

  def with_project(project)
    Project.transaction do
      project.lock!
      actor = fresh_actor
      raise Forbidden, "The identity is no longer active" unless actor.status == "active"
      raise Forbidden, "Project is outside this tenant" unless project.organization_id == actor.organization_id
      yield project, AccessPolicy.new(actor)
    end
  end

  def fresh_actor = User.find(@actor.id)
  def eligible_user(id) = User.where(organization_id: @actor.organization_id, status: "active").find(id)
  # Until real authentication exists, administration must stay with someone who
  # can actually enter this local demo; other active employees may collaborate.
  def eligible_administrator(id) = User.where(organization_id: @actor.organization_id, status: "active", demo_identity: true).find(id)
  def require_permission!(allowed) = (raise Forbidden, "This project operation is outside your access scope" unless allowed)

  def grant_lead(project, user)
    RoleAssignment.create!(organization_id: project.organization_id, user: user, role: "project_lead", scope_type: "project", project: project)
  end
end
