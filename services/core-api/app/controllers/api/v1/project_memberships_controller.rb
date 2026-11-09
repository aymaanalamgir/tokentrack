module Api
  module V1
    class ProjectMembershipsController < BaseController
      def index
        project = policy.projects.find(params[:project_id])
        state = params.fetch(:state, "active")
        if state != "active"
          return unless authorize!(policy.project_administrator?(project))
          return render_error(:invalid_state, "State must be active, past, or all", :unprocessable_content) unless %w[past all].include?(state)
        end
        memberships = project.project_memberships
        memberships = memberships.active if state == "active"
        memberships = memberships.past if state == "past"
        if params[:q].present?
          memberships = memberships.joins(:user).where("users.name ILIKE ? OR users.job_function ILIKE ?", *Array.new(2, "%#{User.sanitize_sql_like(params[:q])}%"))
        end
        if params[:team].present?
          homes = OrganizationalMembership.where(organization_id: policy.organization_id, is_primary: true)
          memberships = params[:team] == "unassigned" ? memberships.where.not(user_id: homes.select(:user_id)) : memberships.where(user_id: homes.where(organizational_unit_id: params[:team]).select(:user_id))
        end
        memberships, meta = page(memberships.order(joined_at: :desc, id: :asc))
        render_data(memberships.includes(user: WorkspacePresenter::DIRECTORY_INCLUDES).map { |m| presenter.membership(m, project) }, meta: meta)
      end

      def create
        project = policy.projects.find(params[:project_id])
        attrs = params.require(:membership).permit(:user_id, :project_role)
        record = ProjectManagement.new(current_user).add_member(project, attrs.require(:user_id), attrs[:project_role])
        render_data(presenter.membership(record, project), status: :created)
      end

      def update
        project = policy.projects.find(params[:project_id])
        record = ProjectManagement.new(current_user).update_member(project, params[:id], params.require(:membership).require(:project_role))
        render_data(presenter.membership(record, project))
      end

      def destroy
        project = policy.projects.find(params[:project_id])
        record = ProjectManagement.new(current_user).remove_member(project, params[:id])
        # An administrator may remove their own membership when another admin
        # remains. Never serialize using grants cached before that revocation.
        @policy = AccessPolicy.new(User.find(current_user.id))
        @presenter = WorkspacePresenter.new(@policy)
        render_data({ id: record.id, left_at: record.left_at, removed: true })
      end
    end
  end
end
