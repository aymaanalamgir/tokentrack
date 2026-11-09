module Api
  module V1
    class UsersController < BaseController
      def index
        people = policy.users
        people = people.where("name ILIKE ?", "%#{User.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
        people, meta = page(people.order(:name))
        render_data(people.includes(*WorkspacePresenter::USER_INCLUDES).map { |u| presenter.user(u) }, meta: meta)
      end

      def show
        user = policy.users.includes(*WorkspacePresenter::USER_INCLUDES).find(params[:id])
        return unless authorize!(policy.profile?(user))
        return unless params[:view] != "management" || authorize!(policy.management_profile?(user))
        projects = policy.projects.where(id: ProjectMembership.where(organization_id: policy.organization_id, user_id: user.id).select(:project_id))
        render_data(presenter.user(user).merge(projects: projects.includes(WorkspacePresenter::PROJECT_INCLUDES).order(:name).map { |p| presenter.project(p).merge(member_role: p.project_memberships.find { |m| m.user_id == user.id }&.project_role) }, can_view_reporting: policy.reporting_context?(user)))
      end

      def reporting_context
        user = policy.users.find(params[:id])
        return unless authorize!(policy.reporting_context?(user))
        ancestors = []
        frontier = [user.id]
        seen = [user.id]
        until frontier.empty?
          relationships = ReportingRelationship.where(organization_id: policy.organization_id, report_id: frontier).includes(:manager).to_a
          ancestors += relationships.reject { |r| seen.include?(r.manager_id) }.map { |r| presenter.person_link(r.manager).merge(report_id: r.report_id, relationship_type: r.relationship_type) }
          frontier = relationships.map(&:manager_id) - seen
          seen |= frontier
        end
        reports = ReportingRelationship.where(organization_id: policy.organization_id, manager_id: user.id).includes(report: WorkspacePresenter::USER_INCLUDES).filter_map do |r|
          presenter.user(r.report).merge(relationship_type: r.relationship_type) if policy.profile?(r.report)
        end
        render_data({ person: presenter.person_link(user), ancestors: ancestors, direct_reports: reports })
      end
    end
  end
end
