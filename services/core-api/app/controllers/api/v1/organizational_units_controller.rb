module Api
  module V1
    class OrganizationalUnitsController < BaseController
      def index
        scope = params[:managed] == "true" ? policy.units.where(id: policy.managed_unit_ids) : policy.units
        units, meta = page(scope.order(:name))
        render_data(units.map { |u| presenter.unit(u) }, meta: meta)
      end

      def show
        unit = policy.units.find(params[:id])
        return unless authorize!(policy.unit?(unit))
        members = policy.users.joins(:organizational_memberships).where(organizational_memberships: { organizational_unit_id: unit.id }).distinct
        roster, meta = page(members.order(:name))
        projects = policy.projects.where(id: ProjectMembership.where(organization_id: policy.organization_id, user_id: members.select(:id)).select(:project_id))
        render_data(presenter.unit(unit, members: members).merge(
          members: roster.includes(*WorkspacePresenter::USER_INCLUDES).map { |u| presenter.user(u, directory_only: !policy.team_roster?(unit)) },
          children: policy.units.where(parent_unit_id: unit.id).order(:name).map { |u| presenter.unit(u) },
          projects: projects.includes(WorkspacePresenter::PROJECT_INCLUDES).order(:name).limit(20).map { |p| presenter.project(p) },
          members_meta: meta
        ))
      end
    end
  end
end
