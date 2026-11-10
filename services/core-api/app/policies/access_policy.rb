require "digest"

# One request-scoped policy combines explicit grants. Job titles and project
# membership labels never grant management, editing, or financial authority.
class AccessPolicy
  attr_reader :actor, :organization_id

  def initialize(actor)
    @actor = actor
    @organization_id = actor.organization_id
  end

  def grants
    @grants ||= actor.role_assignments.includes(:organizational_unit,:project).to_a
  end

  def organization_viewer? = grants.any? { |g| g.role == "organization_viewer" }
  def financial_operator? = grants.any? { |g| g.role == "financial_operator" && g.scope_type == "organization" && g.organization_id == organization_id }
  def budget_org_reader? = financial_operator? || grants.any? { |g| g.role=='organization_budget_reader' && g.scope_type=='organization' }
  def allowance_direct_ids
    @allowance_direct_ids ||= manager? ? ReportingRelationship.where(organization_id:organization_id,manager_id:actor.id,relationship_type:'line_manager').pluck(:report_id) : []
  end
  def allowance_read_user_ids
    return User.where(organization_id:organization_id).pluck(:id) if financial_operator?
    direct=allowance_direct_ids
    [actor.id]+direct
  end
  def allowance_read?(user) = user.organization_id==organization_id && allowance_read_user_ids.include?(user.id)
  def allowance_maximum(user,month)
    return nil unless actor.status=='active' && user.organization_id==organization_id
    return :unlimited if financial_operator?
    return nil if actor.id==user.id || !allowance_direct_ids.include?(user.id)
    home=user.organizational_memberships.find(&:is_primary)
    return nil unless home
    (@allowance_month_grants ||= {})[month] ||= AllowanceDelegation.active.where(organization_id:organization_id,manager_id:actor.id).where('effective_from_month<=? AND effective_until_month>=?',month,month).to_a
    @allowance_month_grants[month].filter_map do |delegation|
      next unless grants.any? { |g|g.role=='team_manager' && g.organizational_unit_id==delegation.organizational_unit_id }
      delegation.maximum_amount if ((@allowance_unit_subtrees ||= {})[delegation.organizational_unit_id] ||= Hierarchy.unit_ids(organization_id,[delegation.organizational_unit_id])).include?(home.organizational_unit_id)
    end.max
  end
  def manage_allowance?(user,amount,month)
    cap=allowance_maximum(user,month)
    cap==:unlimited || (cap && amount<=cap)
  end
  def budget_unit_ids = grants.select { |g| g.role == "team_budget_reader" }.map(&:organizational_unit_id)
  def budget_project_ids = grants.select { |g| g.role == "project_budget_reader" }.map(&:project_id)
  def manager? = grants.any? { |g| g.role == "team_manager" }
  def project_lead? = grants.any? { |g| g.role == "project_lead" }
  def persona = organization_viewer? ? "leadership" : manager? ? "manager" : project_lead? ? "project_lead" : "employee"
  def organization?(record) = record.id == organization_id
  def own_access?(user) = user.id == actor.id && user.organization_id == organization_id

  def managed_unit_ids
    @managed_unit_ids ||= Hierarchy.unit_ids(organization_id, grants.select { |g| g.role == "team_manager" }.map(&:organizational_unit_id))
  end

  def managed_user_ids
    @managed_user_ids ||= ([actor.id] + OrganizationalMembership.where(organization_id: organization_id, organizational_unit_id: managed_unit_ids).pluck(:user_id) + (manager? ? Hierarchy.report_ids(organization_id, [actor.id]) : [])).uniq
  end

  def projects
    base = Project.where(organization_id: organization_id)
    return base if organization_viewer?
    membership_ids = ProjectMembership.active.where(organization_id: organization_id, user_id: manager? ? managed_user_ids : actor.id).select(:project_id)
    grant_ids = grants.filter_map { |g| g.project_id if g.role == "project_lead" }
    base.where(id: membership_ids).or(base.where(id: grant_ids))
  end

  def project?(project) = project.organization_id == organization_id && projects.exists?(id: project.id)
  def create_project? = grants.any? { |g| g.role == "project_creator" && g.scope_type == "organization" && g.organization_id == organization_id }
  def project_administrator?(project) = project.organization_id == organization_id && grants.any? { |g| g.role == "project_lead" && g.project_id == project.id }
  def edit_project?(project) = project_administrator?(project) && !project.archived?
  def manage_project_members?(project) = edit_project?(project)
  def transfer_project?(project) = edit_project?(project)
  def lifecycle_project?(project) = project_administrator?(project)

  def management_profile?(user)
    user.organization_id == organization_id && (organization_viewer? || managed_user_ids.include?(user.id))
  end

  def directory_ids
    @directory_ids ||= begin
      own_units = actor.organizational_memberships.pluck(:organizational_unit_id)
      colleagues = OrganizationalMembership.where(organization_id: organization_id, organizational_unit_id: own_units).pluck(:user_id)
      collaborators = ProjectMembership.active.where(organization_id: organization_id, project_id: projects.select(:id)).pluck(:user_id)
      # Manager ancestry is useful directory context, not an implicit management grant.
      ancestors = []
      frontier = [actor.id]
      until frontier.empty?
        frontier = ReportingRelationship.where(organization_id: organization_id, report_id: frontier).where.not(manager_id: ancestors).pluck(:manager_id)
        ancestors |= frontier
      end
      (managed_user_ids + colleagues + collaborators + ancestors).uniq
    end
  end

  def users
    base = User.where(organization_id: organization_id)
    organization_viewer? ? base : base.where(id: directory_ids)
  end

  def profile?(user) = user.organization_id == organization_id && (organization_viewer? || directory_ids.include?(user.id))
  def reporting_context?(user) = management_profile?(user)

  def units
    base = OrganizationalUnit.where(organization_id: organization_id)
    return base if organization_viewer?
    visible_ids = OrganizationalMembership.where(organization_id: organization_id, user_id: directory_ids).select(:organizational_unit_id)
    base.where(id: visible_ids).or(base.where(id: managed_unit_ids))
  end

  def unit?(unit) = unit.organization_id == organization_id && units.exists?(id: unit.id)
  def team_roster?(unit) = unit.organization_id == organization_id && (organization_viewer? || managed_unit_ids.include?(unit.id))

  def navigation
    items = [{ label: "Overview", href: "/", icon: "overview" }, { label: "Projects", href: "/projects", icon: "projects" }]
    items << { label: manager? ? "My teams" : "Teams", href: "/teams", icon: "teams" } if organization_viewer? || manager?
    items << { label: "People", href: "/people", icon: "teams" } if organization_viewer? || manager?
    items + [
      { label: organization_viewer? ? "Organization" : "My organization", href: "/organization", icon: "organization" },
      { label: "Profile & access", href: "/profile", icon: "profile" },
      { label: "Analytics", href: "/analytics", icon: "analytics" },
      { label: "Budgets", href: "/budgets", icon: "budgets" },
      { label: "Requests", href: "/requests", icon: "requests" },
      { label: "Settings", href: "/settings", icon: "settings" }
    ]
  end

  def access_summary
    permissions = ["profile.read.self", "access.read.self", "projects.read.assigned", "directory.read.context"]
    permissions += ["organization.read", "employees.read.organization"] if organization_viewer?
    permissions += ["teams.read.managed", "employees.read.managed", "reporting.read.managed"] if manager?
    permissions += ["projects.read.led", "projects.edit.led"] if project_lead?
    permissions += ["projects.members.manage", "projects.ownership.transfer", "projects.lifecycle.manage"] if project_lead?
    permissions << "projects.create.organization" if create_project?
    permissions << "allowances.read.self"
    permissions << "allowances.allocate.self"
    permissions << "allowances.read.managed" if manager?
    permissions << "finance.read.accounts.scoped" if budget_org_reader? || budget_unit_ids.any? || budget_project_ids.any?
    permissions << "finance.manage.organization" if financial_operator?
    {
      persona: persona,
      scope_key: Digest::SHA256.hexdigest([grants.map { |g| [g.id, g.role, g.organizational_unit_id, g.project_id] }.sort_by(&:first), AllowanceDelegation.active.where(organization_id:organization_id,manager_id:actor.id).order(:id).pluck(:id,:maximum_amount,:effective_from_month,:effective_until_month), organization_viewer? ? [] : projects.order(:id).pluck(:id), organization_viewer? ? [] : directory_ids.sort].to_json),
      grants: grants.map { |g| { role: g.role, scope_type: g.scope_type, scope_id: g.organizational_unit_id || g.project_id || (g.scope_type == "self" ? actor.id : organization_id), scope_name: g.organizational_unit&.name || g.project&.name || (g.scope_type == "self" ? actor.name : actor.organization.name) } },
      capabilities: permissions,
      restricted: ["Organization administration", "Financial approvals (not implemented)", "Unrelated analytics and unauthorized funding allocations"] + (organization_viewer? ? [] : ["Unrelated employees' private profiles"]),
      navigation: navigation,
      visibility: { directory: "Names, titles, job functions, and relevant team/project context", management: "Own profile, explicitly managed teams/reports, or organization viewer scope", private: "Access grants are visible only to their owner. Analytics are scoped to self, managed people and explicitly led projects. Funding and financial mutation require separate financial_operator authority." }
    }
  end
end
