module Api
  module V1
    class OrganizationsController < BaseController
      def show
        organization = Organization.where(id: policy.organization_id).find(params[:id])
        return unless authorize!(policy.organization?(organization))
        render_data(presenter.organization(organization).merge(scope: policy.organization_viewer? ? "organization" : "authorized context", employee_count: policy.users.count, unit_count: policy.units.count, project_count: policy.projects.count))
      end
    end
  end
end
