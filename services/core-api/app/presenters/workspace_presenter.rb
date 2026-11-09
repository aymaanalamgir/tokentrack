class WorkspacePresenter
  USER_INCLUDES = [{ organizational_memberships: :organizational_unit }, { manager_relationships: :manager }].freeze
  PROJECT_INCLUDES = { project_memberships: { user: USER_INCLUDES } }.freeze

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
      primary_team: primary && unit_link(primary.organizational_unit)
    )
    if full
      result.merge!(record.slice(:email, :status))
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
    memberships = record.project_memberships
    teams = memberships.flat_map { |m| m.user.organizational_memberships.map(&:organizational_unit) }.uniq(&:id)
    record.slice(:id, :name, :slug, :description, :status).merge(
      contributor_count: memberships.size,
      leads: memberships.select { |m| %w[owner lead].include?(m.project_role) }.map { |m| person_link(m.user) },
      teams: teams.map { |team| unit_link(team) },
      my_role: memberships.find { |m| m.user_id == @policy.actor.id }&.project_role,
      can_edit: @policy.edit_project?(record)
    )
  end

  def project_members(record, memberships: nil)
    (memberships || record.project_memberships).map { |m| user(m.user, directory_only: true).merge(project_role: m.project_role) }
  end

  private

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
