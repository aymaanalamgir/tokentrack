class WorkspacePresenter
  DIRECTORY_INCLUDES = [{ organizational_memberships: :organizational_unit }].freeze
  USER_INCLUDES = [*DIRECTORY_INCLUDES, { manager_relationships: :manager }, { project_memberships: :project }].freeze
  PROJECT_INCLUDES = :created_by

  def initialize(policy)
    @policy = policy
  end

  def organization(record)
    record.slice(:id, :name, :slug, :description).merge(demo: record.demo)
  end

  def user(record, directory_only: false)
    full = !directory_only && @policy.management_profile?(record)
    memberships = record.organizational_memberships
    primary = memberships.find(&:is_primary?)
    result = record.slice(:id, :name, :job_title, :job_function).merge(
      visibility: full ? (record.id == @policy.actor.id ? "self" : "management") : "directory",
      can_view: @policy.profile?(record),
      primary_team: primary && unit_link(primary.organizational_unit)
    )
    if full
      result.merge!(record.slice(:email, :status))
      @visible_project_ids ||= @policy.projects.pluck(:id).to_set
      result[:project_assignments] = record.project_memberships.filter_map do |membership|
        project = membership.project
        project.slice(:id, :name, :status).merge(project_role: membership.project_role) if @visible_project_ids.include?(project.id)
      end
      result[:memberships] = memberships.map { |m| unit_link(m.organizational_unit).merge(is_primary: m.is_primary, membership_type: m.membership_type) }
      result[:managers] = record.manager_relationships.map { |r| person_link(r.manager).merge(relationship_type: r.relationship_type) }
    end
    result
  end

  def person_link(record)
    record.slice(:id, :name, :job_title).merge(can_view: @policy.profile?(record))
  end

  def unit_link(record)
    record.slice(:id, :name, :unit_type, :parent_unit_id)
  end

  def unit(record, members: nil)
    @unit_counts ||= OrganizationalMembership.where(organization_id: @policy.organization_id, user_id: @policy.users.select(:id)).group(:organizational_unit_id).count
    @unit_managers ||= RoleAssignment.where(organization_id: @policy.organization_id, role: "team_manager").includes(:user).group_by(&:organizational_unit_id)
    unit_link(record).merge(description: record.description, member_count: members ? members.count : @unit_counts.fetch(record.id, 0), subtree_member_count: subtree_counts.fetch(record.id, 0), roster_visibility: @policy.team_roster?(record) ? "management" : "directory", managers: @unit_managers.fetch(record.id, []).map { |grant| person_link(grant.user) })
  end

  def project(record)
    stats = project_statistics
    memberships = stats[:counts].fetch(record.id, 0)
    admins = stats[:admins].fetch(record.id, [])
    record.slice(:id, :name, :slug, :description, :status, :created_by_id).merge(
      contributor_count: memberships,
      leads: stats[:leads].fetch(record.id, []).map { |m| person_link(m.user) },
      administrators: admins.map { |g| person_link(g.user) },
      teams: stats[:teams].fetch(record.id, []),
      my_role: stats[:mine][record.id],
      restore_status: record.archived_from_status || "active",
      can_edit: @policy.edit_project?(record),
      permissions: {
        edit: @policy.edit_project?(record),
        members_manage: @policy.manage_project_members?(record),
        ownership_transfer: @policy.transfer_project?(record),
        lifecycle_manage: @policy.lifecycle_project?(record),
        history: @policy.project_administrator?(record)
      },
      available_statuses: @policy.lifecycle_project?(record) ? Project::TRANSITIONS.fetch(record.status) : []
    )
  end

  def membership(record, project)
    admin_ids = project_statistics[:admins].fetch(project.id, []).map(&:user_id)
    allowed = @policy.manage_project_members?(project) && record.left_at.nil?
    {
      id: record.id, user: user(record.user, directory_only: true), project_role: record.project_role,
      joined_at: record.joined_at, left_at: record.left_at, status: record.left_at ? "past" : "active",
      administrator: admin_ids.include?(record.user_id),
      can_update: allowed,
      can_remove: allowed && (!admin_ids.include?(record.user_id) || admin_ids.size > 1)
    }
  end

  def project_members(record, memberships: nil)
    (memberships || record.active_project_memberships).map do |m|
      user(m.user, directory_only: true).merge(project_role: m.project_role)
    end
  end

  def project_groups(record)
    org = ApplicationRecord.connection.quote(@policy.organization_id)
    project = ApplicationRecord.connection.quote(record.id)
    ApplicationRecord.connection.select_all(<<~SQL).map do |row|
      SELECT u.id, u.name, u.unit_type, u.parent_unit_id, COUNT(m.id) AS member_count
      FROM business.project_memberships m
      LEFT JOIN business.organizational_memberships h ON h.user_id = m.user_id AND h.organization_id = m.organization_id AND h.is_primary
      LEFT JOIN business.organizational_units u ON u.id = h.organizational_unit_id AND u.organization_id = m.organization_id
      WHERE m.project_id = #{project} AND m.organization_id = #{org} AND m.left_at IS NULL
      GROUP BY u.id ORDER BY u.name NULLS LAST
    SQL
      { unit: row["id"] ? row.slice("id", "name", "unit_type", "parent_unit_id") : { id: "unassigned", name: "No home team", unit_type: "unassigned", parent_unit_id: nil }, member_count: row["member_count"].to_i }
    end
  end

  private

  # Aggregate summaries once per response instead of loading every employee in
  # every listed project. Participant details are fetched in bounded pages.
  def project_statistics
    @project_statistics ||= begin
      ids = @policy.projects.select(:id)
      active = ProjectMembership.active.where(organization_id: @policy.organization_id, project_id: ids)
      teams = OrganizationalMembership.joins(:organizational_unit).joins("JOIN business.project_memberships pm ON pm.user_id = organizational_memberships.user_id AND pm.organization_id = organizational_memberships.organization_id AND pm.left_at IS NULL")
        .where(organization_id: @policy.organization_id, is_primary: true).where("pm.project_id IN (#{ids.to_sql})")
        .distinct.pluck("pm.project_id", "organizational_units.id", "organizational_units.name", "organizational_units.unit_type", "organizational_units.parent_unit_id")
      {
        counts: active.group(:project_id).count,
        mine: active.where(user_id: @policy.actor.id).pluck(:project_id, :project_role).to_h,
        leads: active.where(project_role: %w[owner lead]).includes(:user).group_by(&:project_id),
        admins: RoleAssignment.where(organization_id: @policy.organization_id, project_id: ids, role: "project_lead").includes(:user).group_by(&:project_id),
        teams: teams.group_by(&:first).transform_values { |rows| rows.map { |_, id, name, type, parent| { id: id, name: name, unit_type: type, parent_unit_id: parent } } }
      }
    end
  end

  def subtree_counts
    @subtree_counts ||= begin
      org = ApplicationRecord.connection.quote(@policy.organization_id)
      rows = ApplicationRecord.connection.select_rows(<<~SQL)
        WITH RECURSIVE descendants(root_id, id) AS (
          SELECT id, id FROM business.organizational_units WHERE id IN (#{@policy.units.select(:id).to_sql})
          UNION
          SELECT d.root_id, u.id FROM descendants d JOIN business.organizational_units u ON u.parent_unit_id = d.id
            WHERE u.organization_id = #{org}
        )
        SELECT d.root_id, COUNT(DISTINCT m.user_id) FROM descendants d
          JOIN business.organizational_memberships m ON m.organizational_unit_id = d.id AND m.organization_id = #{org}
          WHERE m.user_id IN (#{@policy.users.select(:id).to_sql}) GROUP BY d.root_id
      SQL
      rows.to_h.transform_values(&:to_i)
    end
  end
end
