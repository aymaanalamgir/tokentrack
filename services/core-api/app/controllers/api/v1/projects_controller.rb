module Api
  module V1
    class ProjectsController < BaseController
      def index
        projects = policy.projects
        projects = projects.where(status: params[:status]) if params[:status].present?
        projects = projects.where("projects.name ILIKE ?", "%#{Project.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
        if params[:department].present?
          unit = policy.units.find(params[:department])
          members = OrganizationalMembership.where(organization_id: policy.organization_id, organizational_unit_id: Hierarchy.unit_ids(policy.organization_id, [unit.id])).select(:user_id)
          projects = projects.where(id: ProjectMembership.where(organization_id: policy.organization_id, user_id: members).select(:project_id))
        end
        projects = projects.where(id: current_user.project_memberships.select(:project_id)) if params[:membership] == "mine"
        projects = projects.where(id: policy.grants.filter_map { |g| g.project_id if g.role == "project_lead" }) if params[:membership] == "led"
        projects, meta = page(projects.order(:name))
        render_data(projects.includes(WorkspacePresenter::PROJECT_INCLUDES).map { |p| presenter.project(p) }, meta: meta)
      end

      def show
        project = policy.projects.includes(WorkspacePresenter::PROJECT_INCLUDES).find(params[:id])
        return unless authorize!(policy.project?(project))
        memberships, meta = page(project.project_memberships.order(:id))
        memberships = memberships.includes(user: WorkspacePresenter::USER_INCLUDES)
        # Participant labels describe collaboration. Only explicit role grants allow editing.
        render_data(presenter.project(project).merge(members: presenter.project_members(project, memberships: memberships), members_meta: meta, role_assignments: RoleAssignment.where(organization_id: policy.organization_id, project_id: project.id).includes(:user).map { |g| { role: g.role, user: presenter.person_link(g.user) } }))
      end

      def update
        project = policy.projects.find(params[:id])
        return unless authorize!(policy.edit_project?(project))
        project.update!(params.require(:project).permit(:name, :description, :status))
        project = policy.projects.includes(WorkspacePresenter::PROJECT_INCLUDES).find(project.id)
        render_data(presenter.project(project))
      end
    end
  end
end
