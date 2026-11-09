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
          projects = projects.where(id: ProjectMembership.active.where(organization_id: policy.organization_id, user_id: members).select(:project_id))
        end
        projects = projects.where(id: current_user.project_memberships.select(:project_id)) if params[:membership] == "mine"
        projects = projects.where(id: policy.grants.filter_map { |g| g.project_id if g.role == "project_lead" }) if params[:membership] == "led"
        projects, meta = page(projects.order(:name))
        render_data(projects.includes(WorkspacePresenter::PROJECT_INCLUDES).map { |p| presenter.project(p) }, meta: meta)
      end

      def create
        return unless authorize!(policy.create_project?)
        record = ProjectManagement.new(current_user).create(params.require(:project).permit(:name, :slug, :description, :status, :initial_lead_id).to_h)
        @policy = AccessPolicy.new(User.find(current_user.id))
        @presenter = WorkspacePresenter.new(@policy)
        render_data(presenter.project(record), status: :created)
      end

      def eligible_users
        if params[:id]
          record = policy.projects.find(params[:id])
          return unless authorize!(policy.manage_project_members?(record))
        else
          return unless authorize!(policy.create_project?)
        end
        people = User.where(organization_id: policy.organization_id, status: "active")
        people = people.where(demo_identity: true) if !record || params[:include_members] == "true"
        people = people.where.not(id: record.active_project_memberships.select(:user_id)) if record && params[:include_members] != "true"
        people = people.where("name ILIKE ? OR job_title ILIKE ?", *Array.new(2, "%#{User.sanitize_sql_like(params[:q].to_s)}%")) if params[:q].present?
        people, meta = page(people.order(:name))
        render_data(people.includes(*WorkspacePresenter::DIRECTORY_INCLUDES).map { |u| presenter.user(u, directory_only: true) }, meta: meta)
      end

      def transfer_ownership
        record = policy.projects.find(params[:id])
        ProjectManagement.new(current_user).transfer(record, params.require(:user_id))
        @policy = AccessPolicy.new(User.find(current_user.id))
        @presenter = WorkspacePresenter.new(@policy)
        render_data(presenter.project(record))
      end

      def team_groups
        record = policy.projects.find(params[:id])
        render_data(presenter.project_groups(record))
      end

      def show
        project = policy.projects.includes(WorkspacePresenter::PROJECT_INCLUDES).find(params[:id])
        return unless authorize!(policy.project?(project))
        memberships, meta = page(project.active_project_memberships.order(:id))
        memberships = memberships.includes(user: WorkspacePresenter::DIRECTORY_INCLUDES)
        # Participant labels describe collaboration. Only explicit role grants allow editing.
        render_data(presenter.project(project).merge(members: presenter.project_members(project, memberships: memberships), members_meta: meta, role_assignments: RoleAssignment.where(organization_id: policy.organization_id, project_id: project.id).includes(:user).map { |g| { role: g.role, user: presenter.person_link(g.user) } }))
      end

      def update
        project = policy.projects.find(params[:id])
        ProjectManagement.new(current_user).update(project, params.require(:project).permit(:name, :description, :status).to_h)
        project = policy.projects.includes(WorkspacePresenter::PROJECT_INCLUDES).find(project.id)
        render_data(presenter.project(project))
      end
    end
  end
end
