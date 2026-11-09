module Api
  module V1
    class MeController < BaseController
      def show
        render_data({ user: presenter.user(current_user), organization: presenter.organization(current_user.organization), access: policy.access_summary })
      end

      def access
        render_data(policy.access_summary)
      end

      def overview
        projects = policy.projects
        people = policy.organization_viewer? ? policy.users : policy.users.where(id: policy.manager? ? policy.managed_user_ids : policy.directory_ids)
        counts = case policy.persona
        when "leadership"
          [["Employees", policy.users.count], ["Organizational units", policy.units.count], ["Active projects", projects.where(status: "active").count]]
        when "manager"
          [["Managed units", policy.managed_unit_ids.size], ["Direct reports", current_user.report_relationships.count], ["Team members", policy.managed_user_ids.size], ["Active team projects", projects.where(status: "active").count]]
        when "project_lead"
          led = projects.where(id: policy.grants.filter_map { |g| g.project_id if g.role == "project_lead" })
          [["Led projects", led.count], ["Contributors", ProjectMembership.where(organization_id: policy.organization_id, project_id: led.select(:id)).distinct.count(:user_id)], ["Participating teams", OrganizationalMembership.where(organization_id: policy.organization_id, user_id: ProjectMembership.where(project_id: led.select(:id)).select(:user_id)).distinct.count(:organizational_unit_id)]]
        else
          [["My projects", current_user.project_memberships.count], ["Team memberships", current_user.organizational_memberships.count], ["Access grants", policy.grants.size]]
        end
        render_data({
          persona: policy.persona,
          counts: counts.map { |label, value| { label: label, value: value } },
          units: (policy.manager? && !policy.organization_viewer? ? policy.units.where(id: policy.managed_unit_ids) : policy.units).order(:name).limit(20).map { |u| presenter.unit(u) },
          people: people.includes(*WorkspacePresenter::USER_INCLUDES).order(:name).limit(8).map { |u| presenter.user(u) },
          projects: projects.includes(WorkspacePresenter::PROJECT_INCLUDES).order(:name).limit(6).map { |p| presenter.project(p) }
        })
      end
    end
  end
end
