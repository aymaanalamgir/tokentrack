class UsageReferenceValidation
  def validate(refs)
    org_ids = refs.map { |r| r[:organization_id].downcase }.uniq
    organizations = Organization.where(id: org_ids).pluck(:id).to_set
    users = User.where(id: refs.map { |r| r[:user_id] }).index_by(&:id)
    projects = Project.where(id: refs.filter_map { |r| r[:project_id].presence }).index_by(&:id)
    periods = ProjectMembership.where(organization_id: org_ids, user_id: users.keys, project_id: projects.keys).group_by { |m| [m.organization_id, m.user_id, m.project_id] }
    refs.map do |ref|
      org_id = ref[:organization_id].downcase
      user = users[ref[:user_id].downcase]
      project_id = ref[:project_id].presence&.downcase
      project = projects[project_id]
      code, field, message = if !organizations.include?(org_id)
        ["UNKNOWN_ORGANIZATION", "organization_id", "Organization is not known"]
      elsif !user || user.organization_id != org_id
        ["INVALID_USER_REFERENCE", "user_id", "User does not belong to this organization"]
      elsif user.status != "active"
        ["USER_INELIGIBLE", "user_id", "User is not currently eligible for attribution; historical status is unavailable"]
      elsif project_id && (!project || project.organization_id != org_id)
        ["INVALID_PROJECT_REFERENCE", "project_id", "Project does not belong to this organization"]
      elsif project_id && !periods.fetch([org_id, user.id, project_id], []).any? { |m| m.joined_at <= ref[:time] && (!m.left_at || ref[:time] < m.left_at) }
        ["PROJECT_MEMBERSHIP_NOT_ESTABLISHED", "project_id", "No recorded project membership covers the event time"]
      end
      { key: ref[:key], valid: code.nil?, code: code, field: field, message: message }.compact
    end
  end
end
